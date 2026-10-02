# frozen_string_literal: true

require "rails_helper"
require "socket"

RSpec.describe AIConnections::ConnectOperation do
  let(:user) { create(:user) }

  it "returns an authorize URL whose redirect URI matches the configured callback endpoint" do
    operator = described_class.call(params: { current_user: user, listener_timeout: 0.2 })

    uri = URI.parse(operator.authorize_url)
    params = URI.decode_www_form(uri.query).to_h

    expect(operator.success?).to eq(true)
    expect(uri.host).to eq("auth.openai.com")
    expect(uri.path).to eq("/oauth/authorize")
    callback_uri = URI.parse(params.fetch("redirect_uri"))
    expect(callback_uri.host).to eq(CodexClient::CONFIG.callback_host)
    expect(callback_uri.port).to eq(CodexClient::CONFIG.callback_port)
    expect(callback_uri.path).to eq(CodexClient::CONFIG.callback_path)
    sleep 0.3 # let the listener thread time out and release port 1455 before the next example
  end

  it "fails with a clear error and does not return an authorize_url when port 1455 is already in use" do
    callback_host = Addrinfo.getaddrinfo(CodexClient::CONFIG.callback_host, CodexClient::CONFIG.callback_port, :INET, :STREAM).first.ip_address
    blocker = TCPServer.new(callback_host, CodexClient::CONFIG.callback_port)

    operator = described_class.call(params: { current_user: user, listener_timeout: 0.2 })

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("Port #{CodexClient::CONFIG.callback_port} đang bận, đóng ứng dụng khác đang dùng port này")
    expect(operator.authorize_url).to be_nil
  ensure
    blocker&.close
  end

  it "closes the callback socket when setup fails after the port is bound" do
    operator = described_class.call(params: { listener_timeout: 0.2 })
    callback_host = Addrinfo.getaddrinfo(CodexClient::CONFIG.callback_host, CodexClient::CONFIG.callback_port, :INET, :STREAM).first.ip_address
    rebound_server = TCPServer.new(callback_host, CodexClient::CONFIG.callback_port)

    expect(operator.success?).to eq(false)
    expect(operator.authorize_url).to be_nil
    expect(operator.errors.full_messages.to_sentence).to eq("Không thể khởi tạo kết nối AI. Vui lòng thử lại")
  ensure
    rebound_server&.close
  end
end
