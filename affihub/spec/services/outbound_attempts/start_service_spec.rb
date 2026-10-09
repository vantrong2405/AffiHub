# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundAttempts::StartService, type: :service do
  describe "#call" do
    it "creates and associates a submitting attempt for the current workflow worker" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-1", fencing_token: 3, lease_expires_at: 1.minute.from_now)
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      service.call

      expect(service).to be_success
      expect(service.outbound_attempt.status).to eq("submitting")
      expect(workflow_run.outbound_attempts.sole.attempt_id).to eq(service.outbound_attempt.attempt_id)
    end

    it "returns a publishing attempt with one destination quota reservation" do
      social_destination = create(:social_destination)
      publication = create(:publication, social_destination:)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "running",
        worker_id: "worker-1",
        fencing_token: 3,
        lease_expires_at: 1.minute.from_now
      )
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      expect { service.call }.to change(PublicationQuotaReservation, :count).by(1)

      expect(service.success?).to eq(true)
      expect(service.outbound_attempt.status).to eq("submitting")
      expect(PublicationQuotaReservation.find_by!(publication:).social_destination).to eq(social_destination)
    end

    it "returns failure before creating an attempt when the destination quota is exhausted" do
      social_destination = create(:social_destination)
      create_list(:publication_quota_reservation, 5, social_destination:, reserved_at: 30.minutes.ago)
      publication = create(:publication, social_destination:)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "running",
        worker_id: "worker-1",
        fencing_token: 3,
        lease_expires_at: 1.minute.from_now
      )
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      expect { service.call }.not_to change(OutboundAttempt, :count)

      expect(service.success?).to eq(false)
      expect(workflow_run.outbound_attempts).to be_empty
      expect(PublicationQuotaReservation.where(social_destination:).count).to eq(5)
    end

    it "returns the existing unresolved attempt without creating a second one" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-1", fencing_token: 3, lease_expires_at: 1.minute.from_now)
      attempt = create(:outbound_attempt, workflow_run:, status: "submitting")
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      expect { service.call }.not_to change { workflow_run.outbound_attempts.count }
      expect(service.outbound_attempt).to eq(attempt)
    end

    it "returns failure when a worker has lost its fencing token" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-b", fencing_token: 4, lease_expires_at: 1.minute.from_now)
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      service.call

      expect(service).not_to be_success
      expect(workflow_run.outbound_attempts).to be_empty
    end
  end
end
