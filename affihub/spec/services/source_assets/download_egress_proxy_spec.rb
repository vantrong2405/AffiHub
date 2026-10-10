# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAssets::DownloadEgressProxy, type: :service do
  describe "#start" do
    let(:proxy) { described_class.new }
    let(:upstream_server) { TCPServer.new("127.0.0.1", 0) }
    let(:upstream_handler) do
      Thread.new do
        socket = upstream_server.accept
        socket.write(socket.read(5))
        socket.close
      end
    end

    before do
      proxy_url = proxy.start
      allow(Resolv).to receive(:getaddresses).with("www.youtube.com").and_return([ "142.251.35.4" ])
      upstream_handler
      upstream_socket = TCPSocket.new("127.0.0.1", upstream_server.addr[1])
      allow(Socket).to receive(:tcp).with("142.251.35.4", 443, nil, connect_timeout: 5)
        .and_return(upstream_socket)
      uri = URI.parse(proxy_url)
      @proxy_client = TCPSocket.new(uri.host, uri.port)
      @proxy_client.write("CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
    end

    after do
      @proxy_client&.close
      proxy.stop
      upstream_server.close
      upstream_handler&.join
    end

    it "tunnels HTTPS traffic through the address resolved and pinned by the proxy" do
      expect(@proxy_client.gets).to eq("HTTP/1.1 200 Connection Established\r\n")
      expect(@proxy_client.gets).to eq("\r\n")
      @proxy_client.write("hello")

      expect(@proxy_client.read(5)).to eq("hello")
      expect(Socket).to have_received(:tcp).with("142.251.35.4", 443, nil, connect_timeout: 5)
    end
  end

  describe "#open_upstream" do
    let(:url) { "https://www.youtube.com/watch?v=video-123" }
    let(:addresses) { [ "142.251.35.4" ] }
    let(:proxy) { described_class.new }

    before do
      allow(Resolv).to receive(:getaddresses)
        .with("www.youtube.com")
        .and_return(addresses)
      allow(Socket).to receive(:tcp).and_return(StringIO.new)
    end

    it "connects to a resolved public IP for an allowlisted HTTPS host" do
      proxy.open_upstream(url:)

      expect(Socket).to have_received(:tcp).with("142.251.35.4", 443, nil, connect_timeout: 5)
    end

    context "when the request uses HTTP" do
      let(:url) { "http://www.youtube.com/watch?v=video-123" }

      it "rejects the request without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when the request uses FTP" do
      let(:url) { "ftp://www.youtube.com/video.mp4" }

      it "rejects the request without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when the request uses a port outside the HTTPS allowlist" do
      let(:url) { "https://www.youtube.com:8443/watch?v=video-123" }

      it "rejects the request without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when the request host is outside the configured allowlist" do
      let(:url) { "https://videos.example.test/watch/123" }

      it "rejects the request before DNS resolution" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Resolv).not_to have_received(:getaddresses)
        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a loopback address" do
      let(:addresses) { [ "127.0.0.1" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to an IPv6 loopback address" do
      let(:addresses) { [ "::1" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a private address" do
      let(:addresses) { [ "10.0.0.4" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to an IPv6 private address" do
      let(:addresses) { [ "fd00::4" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a link-local address" do
      let(:addresses) { [ "169.254.10.20" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to an IPv6 link-local address" do
      let(:addresses) { [ "fe80::20" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a reserved address" do
      let(:addresses) { [ "240.0.0.1" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to an IPv6 documentation address" do
      let(:addresses) { [ "2001:db8::1" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to the IPv6 NAT64 prefix" do
      let(:addresses) { [ "64:ff9b::a9fe:a9fe" ] }

      it "rejects a translated private destination without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to an IPv6 documentation address from 3fff::/20" do
      let(:addresses) { [ "3fff::1" ] }

      it "rejects the reserved address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a non-global IPv6 special-purpose address" do
      let(:addresses) { [ "100:0:0:1::1" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS resolves to a cloud metadata address" do
      let(:addresses) { [ "169.254.169.254" ] }

      it "rejects the address without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS returns no addresses" do
      let(:addresses) { [] }

      it "rejects the request without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when one DNS answer is public and another is private" do
      let(:addresses) { [ "142.251.35.4", "10.0.0.4" ] }

      it "rejects every address instead of selecting the public answer" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when a redirect targets a host outside the configured allowlist" do
      let(:url) { "https://redirect.example.test/video.mp4" }

      it "rejects the redirect before DNS resolution" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Resolv).not_to have_received(:getaddresses)
        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when a redirect target resolves to a metadata-service IP" do
      let(:url) { "https://www.youtube.com/redirected-video.mp4" }
      let(:addresses) { [ "169.254.169.254" ] }

      it "rejects the redirect without opening an upstream connection" do
        expect { proxy.open_upstream(url:) }
          .to raise_error(described_class::BlockedDestination)

        expect(Socket).not_to have_received(:tcp)
      end
    end

    context "when DNS changes after the public address is resolved" do
      it "connects to the pinned public address without resolving the host again" do
        allow(Resolv).to receive(:getaddresses)
          .with("www.youtube.com")
          .and_return([ "142.251.35.4" ], [ "169.254.169.254" ])

        proxy.open_upstream(url:)

        expect(Resolv).to have_received(:getaddresses).with("www.youtube.com").once
        expect(Socket).to have_received(:tcp)
          .with("142.251.35.4", 443, nil, connect_timeout: 5).once
      end
    end
  end
end
