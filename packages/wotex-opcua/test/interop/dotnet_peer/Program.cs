// Independent OPC UA peer on the OPC Foundation UA-.NETStandard stack for the
// software lanes. It serves the fixture's secure endpoint with the fixture's
// server certificate, a folder whose references need several Browse pages, a
// method that reports the server's live browse continuation points, a method
// that reports how many transmitted requests the Cancel service found, and a
// slow method a client can cancel.
//
// The fixture directory is the one the compiled C peer wrote; the peer reuses
// its CA, CRL and server certificate and writes dotnet-config.json
// there once it listens. It stops when its standard input reaches end of file.
//
// Usage: DotnetPeer FIXTURE_DIRECTORY CHILDREN
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Opc.Ua;
using Opc.Ua.Server;

internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length != 2 || !int.TryParse(args[1], out var children) || children < 1 ||
            children > 1000)
        {
            Console.Error.WriteLine("usage: DotnetPeer FIXTURE_DIRECTORY CHILDREN");
            return 64;
        }

        var fixture = Path.GetFullPath(args[0]);
        var stores = Path.Combine(fixture, "dotnet-stores");
        Directory.CreateDirectory(stores);
        Store(stores, "trusted", Path.Combine(fixture, "ca.der"), Path.Combine(fixture, "clean.crl"));
        Store(stores, "issuers", Path.Combine(fixture, "ca.der"), Path.Combine(fixture, "clean.crl"));
        Directory.CreateDirectory(Path.Combine(stores, "rejected"));

        using var key = System.Security.Cryptography.RSA.Create();
        key.ImportFromPem(File.ReadAllText(Path.Combine(fixture, "server.pem")));
        using var public_certificate = X509CertificateLoader.LoadCertificate(
            File.ReadAllBytes(Path.Combine(fixture, "server.der")));
        var certificate = public_certificate.CopyWithPrivateKey(key);

        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        var endpoint = $"opc.tcp://127.0.0.1:{port}/fixture";
        var configuration = new ApplicationConfiguration
        {
            ApplicationName = "Wotex UA-.NETStandard fixture",
            ApplicationUri = "urn:wotex:fixture:server",
            ApplicationType = ApplicationType.Server,
            SecurityConfiguration = new SecurityConfiguration
            {
                ApplicationCertificate = new CertificateIdentifier { Certificate = certificate },
                TrustedPeerCertificates = new CertificateTrustList
                {
                    StoreType = CertificateStoreType.Directory,
                    StorePath = Path.Combine(stores, "trusted")
                },
                TrustedIssuerCertificates = new CertificateTrustList
                {
                    StoreType = CertificateStoreType.Directory,
                    StorePath = Path.Combine(stores, "issuers")
                },
                RejectedCertificateStore = new CertificateTrustList
                {
                    StoreType = CertificateStoreType.Directory,
                    StorePath = Path.Combine(stores, "rejected")
                },
                AutoAcceptUntrustedCertificates = false,
                // Pinning clients compare the endpoint certificate with the
                // leaf they were given, so the chain is not appended to it.
                SendCertificateChain = false,
                RejectSHA1SignedCertificates = true,
                MinimumCertificateKeySize = 2048
            },
            TransportConfigurations = new TransportConfigurationCollection(),
            TransportQuotas = new TransportQuotas { OperationTimeout = 60000 },
            ServerConfiguration = new ServerConfiguration
            {
                BaseAddresses = { endpoint },
                SecurityPolicies =
                {
                    new ServerSecurityPolicy
                    {
                        SecurityMode = MessageSecurityMode.SignAndEncrypt,
                        SecurityPolicyUri = SecurityPolicies.Basic256Sha256
                    }
                },
                UserTokenPolicies =
                {
                    new UserTokenPolicy(UserTokenType.Anonymous)
                    {
                        PolicyId = "anonymous",
                        SecurityPolicyUri = SecurityPolicies.None
                    }
                },
                MaxBrowseContinuationPoints = 16,
                MaxRegistrationInterval = 0
            }
        };

        await configuration.ValidateAsync(ApplicationType.Server).ConfigureAwait(false);
        var server = new FixtureServer(children);
        try
        {
            await server.StartAsync(configuration).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            for (var cause = exception; cause != null; cause = cause.InnerException)
                Console.Error.WriteLine(cause.GetType().Name + ": " + cause.Message);
            if (exception is ServiceResultException result)
                Console.Error.WriteLine(result.Result.ToLongString());
            return 70;
        }

        var config = new Dictionary<string, object>
        {
            ["endpoint"] = endpoint,
            ["namespace_uri"] = FixtureNodeManager.NamespaceUri,
            ["paged_node_id"] = "nsu=" + FixtureNodeManager.NamespaceUri + ";s=paged",
            ["children"] = children,
            ["object_id"] = "nsu=" + FixtureNodeManager.NamespaceUri + ";s=fixture",
            ["continuation_points_method_id"] = "nsu=" + FixtureNodeManager.NamespaceUri + ";s=continuation_points",
            ["cancel_count_method_id"] = "nsu=" + FixtureNodeManager.NamespaceUri + ";s=cancel_count",
            ["slow_method_id"] = "nsu=" + FixtureNodeManager.NamespaceUri + ";s=slow"
        };
        await File.WriteAllTextAsync(Path.Combine(fixture, "dotnet-config.json"),
            JsonSerializer.Serialize(config)).ConfigureAwait(false);
        Console.WriteLine("dotnet peer ready");

        var stop = new TaskCompletionSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.TrySetResult(); };
        AppDomain.CurrentDomain.ProcessExit += (_, _) => stop.TrySetResult();
        // The owner holds stdin open; its end is the end of the peer.
        _ = Task.Run(() => { Console.In.ReadToEnd(); stop.TrySetResult(); });
        await stop.Task.ConfigureAwait(false);
        await server.StopAsync().ConfigureAwait(false);
        return 0;
    }

    private static void Store(string stores, string name, string certificate, string crl)
    {
        var certs = Path.Combine(stores, name, "certs");
        var crls = Path.Combine(stores, name, "crl");
        Directory.CreateDirectory(certs);
        Directory.CreateDirectory(crls);
        File.Copy(certificate, Path.Combine(certs, Path.GetFileName(certificate)), true);
        File.Copy(crl, Path.Combine(crls, Path.GetFileName(crl)), true);
    }
}

internal sealed class FixtureServer : StandardServer
{
    private readonly int m_children;
    private long m_cancelled;

    public FixtureServer(int children) => m_children = children;

    public long Cancelled => Interlocked.Read(ref m_cancelled);

    protected override MasterNodeManager CreateMasterNodeManager(IServerInternal server,
        ApplicationConfiguration configuration)
    {
        var manager = new FixtureNodeManager(server, configuration, this, m_children);
        return new MasterNodeManager(server, configuration, null, manager);
    }

    public override async Task<CancelResponse> CancelAsync(SecureChannelContext secureChannelContext,
        RequestHeader requestHeader, uint requestHandle, CancellationToken ct)
    {
        var response = await base.CancelAsync(secureChannelContext, requestHeader, requestHandle, ct)
            .ConfigureAwait(false);
        Interlocked.Add(ref m_cancelled, response.CancelCount);
        return response;
    }

    // The server's own count: every active Session's saved browse continuation points.
    public int LiveContinuationPoints()
    {
        var field = typeof(Session).GetField("m_browseContinuationPoints",
            BindingFlags.NonPublic | BindingFlags.Instance) ??
            throw new InvalidOperationException("Session keeps no browse continuation list");
        var total = 0;
        foreach (var session in CurrentInstance.SessionManager.GetSessions())
        {
            if (field.GetValue(session) is System.Collections.ICollection points)
            {
                lock (points.SyncRoot) total += points.Count;
            }
        }
        return total;
    }
}

internal sealed class FixtureNodeManager : CustomNodeManager2
{
    public const string NamespaceUri = "urn:wotex:dotnet-fixture";
    private readonly FixtureServer m_owner;
    private readonly int m_children;

    public FixtureNodeManager(IServerInternal server, ApplicationConfiguration configuration,
        FixtureServer owner, int children) : base(server, configuration, NamespaceUri)
    {
        m_owner = owner;
        m_children = children;
    }

    public override void CreateAddressSpace(IDictionary<NodeId, IList<IReference>> externalReferences)
    {
        lock (Lock)
        {
            if (!externalReferences.TryGetValue(ObjectIds.ObjectsFolder, out var references))
            {
                references = new List<IReference>();
                externalReferences[ObjectIds.ObjectsFolder] = references;
            }

            var paged = new FolderState(null)
            {
                NodeId = new NodeId("paged", NamespaceIndex),
                BrowseName = new QualifiedName("Paged", NamespaceIndex),
                DisplayName = "Paged",
                TypeDefinitionId = ObjectTypeIds.FolderType,
                EventNotifier = EventNotifiers.None
            };
            paged.AddReference(ReferenceTypeIds.Organizes, true, ObjectIds.ObjectsFolder);
            references.Add(new NodeStateReference(ReferenceTypeIds.Organizes, false, paged.NodeId));

            for (var index = 1; index <= m_children; index++)
            {
                var child = new BaseDataVariableState(paged)
                {
                    NodeId = new NodeId($"child{index}", NamespaceIndex),
                    BrowseName = new QualifiedName($"Child{index}", NamespaceIndex),
                    DisplayName = $"Child{index}",
                    TypeDefinitionId = VariableTypeIds.BaseDataVariableType,
                    ReferenceTypeId = ReferenceTypeIds.Organizes,
                    DataType = DataTypeIds.UInt32,
                    ValueRank = ValueRanks.Scalar,
                    Value = (uint)index,
                    AccessLevel = AccessLevels.CurrentRead,
                    UserAccessLevel = AccessLevels.CurrentRead
                };
                paged.AddChild(child);
            }
            AddPredefinedNode(SystemContext, paged);

            var fixture = new BaseObjectState(null)
            {
                NodeId = new NodeId("fixture", NamespaceIndex),
                BrowseName = new QualifiedName("Fixture", NamespaceIndex),
                DisplayName = "Fixture",
                TypeDefinitionId = ObjectTypeIds.BaseObjectType,
                EventNotifier = EventNotifiers.None
            };
            fixture.AddReference(ReferenceTypeIds.Organizes, true, ObjectIds.ObjectsFolder);
            references.Add(new NodeStateReference(ReferenceTypeIds.Organizes, false, fixture.NodeId));

            Method(fixture, "continuation_points", "ContinuationPoints", Array.Empty<Argument>(),
                new[] { Scalar("Count", DataTypeIds.UInt32) },
                (_, _, _, _, outputs) =>
                {
                    outputs[0] = (uint)m_owner.LiveContinuationPoints();
                    return ServiceResult.Good;
                });
            Method(fixture, "cancel_count", "CancelCount", Array.Empty<Argument>(),
                new[] { Scalar("Count", DataTypeIds.UInt32) },
                (_, _, _, _, outputs) =>
                {
                    outputs[0] = (uint)m_owner.Cancelled;
                    return ServiceResult.Good;
                });
            Method(fixture, "slow", "Slow", new[] { Scalar("Milliseconds", DataTypeIds.UInt32) },
                new[] { Scalar("Milliseconds", DataTypeIds.UInt32) },
                (_, _, _, inputs, outputs) =>
                {
                    var milliseconds = (uint)inputs[0];
                    Thread.Sleep((int)Math.Min(milliseconds, 30000));
                    outputs[0] = milliseconds;
                    return ServiceResult.Good;
                });
            AddPredefinedNode(SystemContext, fixture);
        }
    }

    private void Method(BaseObjectState parent, string id, string name, Argument[] inputs,
        Argument[] outputs, GenericMethodCalledEventHandler2 handler)
    {
        var method = new MethodState(parent)
        {
            NodeId = new NodeId(id, NamespaceIndex),
            BrowseName = new QualifiedName(name, NamespaceIndex),
            DisplayName = name,
            ReferenceTypeId = ReferenceTypeIds.HasComponent,
            Executable = true,
            UserExecutable = true
        };
        if (inputs.Length > 0)
        {
            method.InputArguments = new PropertyState<Argument[]>(method)
            {
                NodeId = new NodeId(id + "_inputs", NamespaceIndex),
                BrowseName = BrowseNames.InputArguments,
                DisplayName = BrowseNames.InputArguments,
                TypeDefinitionId = VariableTypeIds.PropertyType,
                ReferenceTypeId = ReferenceTypeIds.HasProperty,
                DataType = DataTypeIds.Argument,
                ValueRank = ValueRanks.OneDimension,
                Value = inputs
            };
        }
        method.OutputArguments = new PropertyState<Argument[]>(method)
        {
            NodeId = new NodeId(id + "_outputs", NamespaceIndex),
            BrowseName = BrowseNames.OutputArguments,
            DisplayName = BrowseNames.OutputArguments,
            TypeDefinitionId = VariableTypeIds.PropertyType,
            ReferenceTypeId = ReferenceTypeIds.HasProperty,
            DataType = DataTypeIds.Argument,
            ValueRank = ValueRanks.OneDimension,
            Value = outputs
        };
        method.OnCallMethod2 = handler;
        parent.AddChild(method);
    }

    private static Argument Scalar(string name, NodeId dataType) =>
        new() { Name = name, DataType = dataType, ValueRank = ValueRanks.Scalar };
}
