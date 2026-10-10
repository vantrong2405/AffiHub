require "rails_helper"

RSpec.describe Telegram::Workers::MonitorService, type: :service do
  describe "#call" do
    let(:worker_status_service) { instance_double(Telegram::Workers::StatusService) }

    before do
      allow(worker_status_service).to receive(:call).and_return(:stopped)
    end

    it 'returns true and enqueues one alert when no healthy worker is registered' do
      automation_control = AutomationControl.current
      service = described_class.new(worker_status_service:)

      expect { service.call }.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("worker_down", nil, nil, {})
        .exactly(1).times

      expect(automation_control.reload.telegram_worker_down_alerted).to eq(true)
    end

    it 'returns true without repeating an alert while workers remain down' do
      automation_control = AutomationControl.current
      automation_control.update!(telegram_worker_down_alerted: true)
      service = described_class.new(worker_status_service:)

      expect { service.call }.not_to have_enqueued_job(Telegram::Alerts::SendJob)

      expect(automation_control.reload.telegram_worker_down_alerted).to eq(true)
    end

    it 'returns true and clears the alert state when a healthy worker returns' do
      automation_control = AutomationControl.current
      automation_control.update!(telegram_worker_down_alerted: true)
      allow(worker_status_service).to receive(:call).and_return(:running)
      service = described_class.new(worker_status_service:)

      expect(service.call).to eq(true)
      expect(automation_control.reload.telegram_worker_down_alerted).to eq(false)
    end

    it 'returns false without alerting when the worker registry is unavailable' do
      allow(worker_status_service).to receive(:call).and_return(:unavailable)
      service = described_class.new(worker_status_service:)
      result = nil

      expect { result = service.call }.not_to have_enqueued_job(Telegram::Alerts::SendJob)

      expect(result).to eq(false)
    end

    it 'returns false without alerting for an unrecognized worker status' do
      allow(worker_status_service).to receive(:call).and_return(:starting)
      service = described_class.new(worker_status_service:)
      result = nil

      expect { result = service.call }.not_to have_enqueued_job(Telegram::Alerts::SendJob)

      expect(result).to eq(false)
    end
  end
end
