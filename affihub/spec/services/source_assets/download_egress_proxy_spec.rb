# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAssets::DownloadEgressProxy, type: :service do
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

      expect(Socket).to have_received(:tcp).with("142.251.35.4", 443, anything)
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
        expect(Socket).to have_received(:tcp).with("142.251.35.4", 443, anything).once
      end
    end
  end
end
