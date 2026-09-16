#!/usr/bin/env escript
%% Injected C07 peer for BEAM ownership tests; never SDK interoperability evidence.
-module(wotex_thread_test_bridge).
-export([main/1]).

main(_) ->
    Root = filename:dirname(escript:script_name()),
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
            Request = json:decode(list_to_binary(Line)),
            ok = file:write_file(filename:join(Root, "requests"), Line, [append]),
            case respond(Root, Mode, State, Petition, Request) of
                {NextState, NextPetition, continue} ->
                    loop(Root, Mode, NextState, NextPetition);
                {_, _, stop} -> ok
            end
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

await_release(Root) ->
    case filelib:is_file(filename:join(Root, "release")) of
        true -> ok;
        false ->
            receive
                eof -> halt(0);
                {line, _} -> await_release(Root)
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
