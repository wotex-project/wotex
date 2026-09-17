#!/usr/bin/env escript
%% Injected C07 peer for BEAM ownership tests; never SDK interoperability evidence.
-module(wotex_thread_test_bridge).
-export([main/1]).

main(_) ->
    Root = filename:dirname(escript:script_name()),
    put(root, Root),
    {ok, ModeBytes} = file:read_file(filename:join(Root, "mode")),
    Mode = string:trim(binary_to_list(ModeBytes)),
    ok = file:write_file(filename:join(Root, "pid"), os:getpid()),
    Parent = self(),
    spawn_link(fun() -> input(Parent) end),
    State = #{<<"role">> => <<"disabled">>, <<"network_name">> => null,
              <<"rloc16">> => null, <<"ipv6_enabled">> => false,
              <<"thread_enabled">> => false, <<"generation">> => 1},
    if Mode =:= "startup_stall" -> timer:sleep(60000); true -> ok end,
    if Mode =:= "startup_wait" -> await_release(Root); true -> ok end,
    case Mode of
        "bad_ready" ->
            write(#{<<"version">> => 2, <<"event">> => <<"ready">>,
                    <<"backend">> => <<"openthread">>, <<"revision">> => <<"bad">>});
        _ ->
            write(#{<<"version">> => 1, <<"event">> => <<"ready">>,
                    <<"backend">> => <<"openthread">>,
                    <<"revision">> => <<"5c8c318627954c99cd1a957a290bbd4b1027d04b">>})
    end,
    loop(Root, Mode, State, none),
    file:write_file(filename:join(Root, "exited"), <<"done">>).

input(Parent) ->
    case io:get_line("") of
        eof -> Parent ! eof;
        Line -> Parent ! {line, Line}, input(Parent)
    end.

loop(Root, Mode, State, Petition) ->
    receive
        eof -> ok;
        {line, Line} ->
            case json:decode(list_to_binary(Line)) of
                #{<<"event">> := _} = Control ->
                    flow(Root, Mode, State, Control),
                    loop(Root, Mode, State, Petition);
                Request ->
                    request(Root, Mode, State, Petition, Request, Line)
            end
    end.

%% Records the exact flow initialization; a request before it is logged as missing.
flow(Root, _Mode, _State, #{<<"version">> := 1, <<"event">> := <<"flow_open">>,
                          <<"session_generation">> := Generation} = Control)
  when map_size(Control) == 3, byte_size(Generation) == 32 ->
    Valid = lists:all(fun(Byte) -> (Byte >= $0 andalso Byte =< $9) orelse
                                       (Byte >= $a andalso Byte =< $f) end,
                      binary_to_list(Generation)),
    Entry = case {Valid, get(flow_open)} of
        {true, undefined} ->
            put(flow_open, true), put(session, Generation), <<Generation/binary, "\n">>;
        _ -> <<"invalid\n">>
    end,
    ok = file:write_file(filename:join(Root, "flow"), Entry, [append]);
flow(Root, Mode, State, #{<<"version">> := 1, <<"event">> := <<"report_ack">>} = Ack)
  when map_size(Ack) == 5 ->
    ok = file:write_file(filename:join(Root, "acks"), [json:encode(Ack), "\n"], [append]),
    %% Stream mode emits one further report per acknowledgement until its count ends.
    case {Mode, get(remaining)} of
        {"stream", Remaining} when is_integer(Remaining), Remaining > 0 ->
            case streams() of
                [Stream | _] -> put(remaining, Remaining - 1), report(Stream, State, 4);
                [] -> ok
            end;
        _ -> ok
    end;
flow(Root, _Mode, _State, _) ->
    ok = file:write_file(filename:join(Root, "flow"), <<"invalid\n">>, [append]).

request(Root, Mode, State, Petition, Request, Line) ->
    ok = file:write_file(filename:join(Root, "requests"), Line, [append]),
    case get(flow_open) of
        true -> ok;
        undefined -> ok = file:write_file(filename:join(Root, "flow"), <<"missing\n">>, [append])
    end,
    case respond(Root, Mode, State, Petition, Request) of
        {NextState, NextPetition, continue} -> loop(Root, Mode, NextState, NextPetition);
        {_, _, stop} -> ok
    end.

respond(_Root, Mode, State, Petition, #{<<"operation">> := <<"open">>} = Request) ->
    if Mode =:= "open_stall" -> timer:sleep(60000); true -> ok end,
    case Mode of
        "open_bad" -> reply(Request, #{<<"role">> => <<"invalid">>});
        "open_error" -> failure(Request, #{<<"code">> => <<"storage_unavailable">>});
        _ -> reply(Request, State)
    end,
    {State, Petition, continue};
respond(_Root, Mode, State, Petition, #{<<"operation">> := <<"close">>} = Request) ->
    if Mode =:= "close_stall" ->
           os:set_signal(sigterm, ignore),
           timer:sleep(60000);
       true -> ok
    end,
    if Mode =:= "slow_close" -> timer:sleep(25); true -> ok end,
    Result = if Mode =:= "close_bad" -> <<"invalid">>; true -> null end,
    reply(Request, Result),
    {State, Petition, stop};
respond(Root, Mode, State, Petition, Request0) ->
    if Mode =:= "wait" -> await_release(Root); true -> ok end,
    Request = case Mode of
        "wrong_id" -> Request0#{<<"id">> := <<"unmatched">>};
        _ -> Request0
    end,
    Operation = maps:get(<<"operation">>, Request),
    if Mode =:= "duplicate" ->
           Result = if Operation =:= <<"inspect">> -> State;
                       true -> <<"disabled">> end,
           reply(Request, Result);
       true -> ok
    end,
    case Mode of
        "bad_json" -> io:put_chars("{bad}\n"), {State, Petition, stop};
        "truncated" -> io:put_chars("{"), {State, Petition, stop};
        "large" -> io:put_chars([lists:duplicate(131072, $x), "\n"]),
                   {State, Petition, stop};
        _ -> operation(Mode, State, Petition, Request, Operation)
    end.

operation(Mode, State, Petition, Request, <<"form_network">>) ->
    case Mode of
        "error" ->
            failure(Request, #{<<"code">> => <<"creation_not_allowed">>,
                               <<"state">> => State}),
            {State, Petition, continue};
        "form_bad" ->
            reply(Request, State), {State, Petition, continue};
        _ ->
            Updated = State#{<<"ipv6_enabled">> := true,
                             <<"thread_enabled">> := true,
                             <<"role">> := <<"leader">>},
            reply(Request, Updated), {Updated, Petition, continue}
    end;
operation(Mode, State, Petition, Request, Operation)
  when Operation =:= <<"management_active_set">>;
       Operation =:= <<"management_pending_set">> ->
    case Mode of
        "error" -> failure(Request, #{<<"code">> => <<"remote_error">>,
                                      <<"status">> => 37});
        "management_bad" ->
            reply(Request, #{<<"accepted">> => true,
                             <<"effective">> => <<"verified">>});
        _ -> reply(Request, #{<<"accepted">> => true,
                              <<"effective">> => <<"not_verified">>})
    end,
    {State, Petition, continue};
operation(Mode, State, Petition, Request, <<"commissioner_start">>) ->
    case Mode of
        "petition_pending" -> {State, Request, continue};
        "petition_stop_wait" -> {State, Request, continue};
        "commissioner_bad" ->
            reply(Request, <<"petition">>), {State, Petition, continue};
        "error" ->
            failure(Request, #{<<"code">> => <<"remote_error">>,
                               <<"status">> => 13}),
            {State, Petition, continue};
        _ -> reply(Request, #{<<"state">> => <<"active">>}),
             {State, Petition, continue}
    end;
operation(Mode, State, Petition, Request, <<"commissioner_stop">>) ->
    if Mode =:= "petition_stop_wait" -> ok;
       true ->
           if Petition =/= none ->
                  failure(Petition, #{<<"code">> => <<"cancelled">>});
              true -> ok
           end,
           reply(Request, #{<<"state">> => <<"disabled">>})
    end,
    {State, none, continue};
operation(Mode, State, Petition, Request, <<"add_joiner">>) ->
    Parameters = maps:get(<<"parameters">>, Request),
    Identity = if Mode =:= "admission_wrong" ->
                   #{<<"type">> => <<"eui64">>,
                     <<"value">> => <<"000000000000002B">>};
                  true -> maps:get(<<"identity">>, Parameters)
               end,
    Lifetime = if Mode =:= "admission_lifetime" -> 1;
                  true -> maps:get(<<"lifetime">>, Parameters)
               end,
    reply(Request, #{<<"identity">> => Identity,
                     <<"lifetime_s">> => Lifetime}),
    {State, Petition, continue};
operation(_Mode, State, Petition, Request, <<"remove_joiner">>) ->
    reply(Request, null), {State, Petition, continue};
operation(Mode, State, Petition, Request, <<"set_enabled">>) ->
    case Mode of
        "error" ->
            failure(Request, #{<<"code">> => <<"remote_error">>,
                               <<"status">> => 253}),
            {State, Petition, continue};
        _ ->
            Parameters = maps:get(<<"parameters">>, Request),
            Thread = maps:get(<<"thread">>, Parameters),
            Role = if Thread -> <<"detached">>;
                      true -> <<"disabled">> end,
            Updated = State#{<<"ipv6_enabled">> := maps:get(<<"ipv6">>, Parameters),
                             <<"thread_enabled">> := Thread,
                             <<"role">> := Role},
            reply(Request, Updated), {Updated, Petition, continue}
    end;
operation(Mode, State, Petition, Request, <<"subscribe_state">>) ->
    Id = maps:get(<<"id">>, Request),
    Generation = case get(stream_generation) of undefined -> 1; Last -> Last + 1 end,
    put(stream_generation, Generation),
    Stream = {Id, Generation},
    put(streams, [Stream | streams()]),
    reply(Request, #{<<"subscription_id">> => Id, <<"generation">> => Generation}),
    report(Stream, State, 0),
    case Mode of
        "stream" -> put(remaining, stream_count());
        "burst" ->
            %% One write places 17 unacknowledged reports ahead of any owner admission.
            Frames = [begin
                          Sequence = next_sequence(),
                          put({last, Id}, Sequence),
                          [json:encode(stream_frame(Stream, report_fields(State, 4, Sequence))), "\n"]
                      end || _ <- lists:seq(1, 17)],
            io:put_chars(Frames);
        "stream_error" ->
            write(stream_frame(Stream, #{<<"event">> => <<"stream_error">>,
                                         <<"code">> => <<"queue_overflow">>})),
            retire(Stream);
        "unsolicited_retire" -> retire(Stream);
        "foreign_report" ->
            write(stream_frame({Id, Generation + 1},
                               report_fields(State, 4, next_sequence())));
        _ -> ok
    end,
    {State, Petition, continue};
operation(_Mode, State, Petition, Request, <<"unsubscribe">>) ->
    Parameters = maps:get(<<"parameters">>, Request),
    Stream = {maps:get(<<"subscription_id">>, Parameters), maps:get(<<"generation">>, Parameters)},
    case lists:member(Stream, streams()) of
        true ->
            put(streams, lists:delete(Stream, streams())),
            retire(Stream),
            reply(Request, null);
        false ->
            failure(Request, #{<<"code">> => <<"subscription_not_found">>})
    end,
    {State, Petition, continue};
operation(Mode, State, Petition, Request, <<"validate_dataset">>) ->
    if Mode =:= "dataset_invalid" ->
           failure(Request, #{<<"code">> => <<"invalid_dataset">>});
       true -> reply(Request, null)
    end,
    {State, Petition, continue};
operation(Mode, State, Petition, Request, <<"get_dataset">>) ->
    case Mode of
        "dataset_invalid" ->
            reply(Request, #{<<"type">> => <<"bytes">>, <<"base64">> => <<"AB==">>});
        "dataset_missing" ->
            failure(Request, #{<<"code">> => <<"dataset_not_found">>});
        _ -> reply(Request, #{<<"type">> => <<"bytes">>, <<"base64">> => <<"+gEA">>})
    end,
    {State, Petition, continue};
operation(Mode, State, Petition, Request, Operation) ->
    case Mode of
        "error" -> failure(Request, #{<<"code">> => <<"remote_error">>,
                                      <<"status">> => 253});
        _ ->
            Values = #{<<"inspect">> => State, <<"state">> => <<"disabled">>,
                       <<"version">> => <<"fixture">>,
                       <<"network_name">> => null, <<"rloc16">> => null},
            reply(Request, maps:get(Operation, Values))
    end,
    {State, Petition, continue}.

streams() -> case get(streams) of undefined -> []; Streams -> Streams end.

stream_count() ->
    {ok, Count} = file:read_file(filename:join(get(root), "report_count")),
    binary_to_integer(string:trim(Count)).

next_sequence() ->
    Sequence = case get(report_sequence) of undefined -> 1; Last -> Last + 1 end,
    put(report_sequence, Sequence),
    Sequence.

report_fields(State, Flags, Sequence) ->
    #{<<"event">> => <<"state">>, <<"report_sequence">> => Sequence, <<"value">> => State,
      <<"metadata">> => #{<<"changed_flags">> => Flags}}.

report({Id, _} = Stream, State, Flags) ->
    Sequence = next_sequence(),
    put({last, Id}, Sequence),
    write(stream_frame(Stream, report_fields(State, Flags, Sequence))).

retire({Id, _} = Stream) ->
    Last = case get({last, Id}) of undefined -> 0; Value -> Value end,
    write(stream_frame(Stream, #{<<"event">> => <<"stream_retired">>,
                                 <<"last_report_sequence">> => Last})).

stream_frame({Id, Generation}, Fields) ->
    Fields#{<<"version">> => 1, <<"session_generation">> => get(session),
            <<"subscription_id">> => Id, <<"generation">> => Generation}.

await_release(Root) ->
    case filelib:is_file(filename:join(Root, "release")) of
        true -> ok;
        false ->
            receive
                eof -> halt(0);
                {line, Line} ->
                    %% Like the native host, close is served while other work waits.
                    case json:decode(list_to_binary(Line)) of
                        #{<<"operation">> := <<"close">>} = Close ->
                            ok = file:write_file(filename:join(Root, "requests"), Line, [append]),
                            reply(Close, null),
                            halt(0);
                        _ -> await_release(Root)
                    end
            after 2 -> await_release(Root)
            end
    end.

reply(Request, Result) ->
    write(#{<<"version">> => 1, <<"id">> => maps:get(<<"id">>, Request),
            <<"ok">> => true, <<"result">> => Result}).

failure(Request, Error) ->
    write(#{<<"version">> => 1, <<"id">> => maps:get(<<"id">>, Request),
            <<"ok">> => false, <<"error">> => Error}).

write(Value) -> io:put_chars([json:encode(Value), "\n"]).
