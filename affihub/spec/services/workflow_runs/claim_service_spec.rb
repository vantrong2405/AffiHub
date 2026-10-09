# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkflowRuns::ClaimService, type: :service do
  describe "#call" do
    it "returns a lease to only one of two simultaneous workers", database_cleaner: :truncation do
      workflow_run = create(:workflow_run)
      worker_ids = %w[worker-a worker-b]
      ready = Queue.new
      start = Queue.new
      results = Queue.new

      threads = worker_ids.map do |worker_id|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            service = described_class.new(workflow_run_id: workflow_run.id, worker_id:)
            service.call
            results << service.success?
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:value)

      expect(2.times.map { results.pop }.count(true)).to eq(1)
    end

    it "returns a higher fencing token when an expired lease is claimed again" do
      workflow_run = create(:workflow_run)
      first = described_class.new(workflow_run_id: workflow_run.id, worker_id: "worker-a")
      first.call
      workflow_run.update!(lease_expires_at: 1.second.ago)
      second = described_class.new(workflow_run_id: workflow_run.id, worker_id: "worker-b")

      second.call

      expect(second.fencing_token).to be > first.fencing_token
    end

    it "returns a publication lease with its destination quota reservation" do
      social_destination = create(:social_destination)
      publication = create(:publication, social_destination:)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish"
      )
      service = described_class.new(workflow_run_id: workflow_run.id, worker_id: "publisher-1")

      expect { service.call }.to change(PublicationQuotaReservation, :count).by(1)

      expect(service.success?).to eq(true)
      expect(workflow_run.reload.status).to eq("running")
      expect(PublicationQuotaReservation.find_by!(publication:).social_destination).to eq(social_destination)
    end

    it "returns failure and blocks a publication when its destination quota is exhausted" do
      social_destination = create(:social_destination)
      create_list(:publication_quota_reservation, 5, social_destination:, reserved_at: 30.minutes.ago)
      publication = create(:publication, social_destination:)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish"
      )
      service = described_class.new(workflow_run_id: workflow_run.id, worker_id: "publisher-1")

      expect { service.call }.not_to change(PublicationQuotaReservation, :count)

      expect(service.success?).to eq(false)
      expect(workflow_run.reload.status).to eq("failed")
      expect(workflow_run.lease_expires_at).to eq(nil)
      expect(publication.reload.status).to eq("failed")
      expect(publication.safe_error_code).to eq("publication_quota_exhausted")
    end

    it "returns one publication lease when two workers compete for the final destination slot", database_cleaner: :truncation do
      social_destination = create(:social_destination)
      create_list(:publication_quota_reservation, 4, social_destination:, reserved_at: 30.minutes.ago)
      first_publication = create(:publication, social_destination:)
      second_publication = create(:publication, social_destination:)
      first_workflow_run = create(:workflow_run, workflowable: first_publication, operation: "publication_publish", stage: "publish")
      second_workflow_run = create(:workflow_run, workflowable: second_publication, operation: "publication_publish", stage: "publish")
      workflow_run_ids = [ first_workflow_run.id, second_workflow_run.id ]
      ready = Queue.new
      start = Queue.new
      results = Queue.new

      threads = workflow_run_ids.map do |workflow_run_id|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            service = described_class.new(workflow_run_id:, worker_id: SecureRandom.uuid)
            service.call
            results << service.success?
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:value)
      outcomes = 2.times.map { results.pop }

      expect(outcomes.count(true)).to eq(1)
      expect(outcomes.count(false)).to eq(1)
      expect(PublicationQuotaReservation.where(social_destination:).count).to eq(5)
      expect(WorkflowRun.where(id: workflow_run_ids, status: "running").count).to eq(1)
    end

    context "when a scheduled Publication is claimed after its Schedule is paused" do
      it "returns it to manual review without claiming or reserving quota" do
        render_version = create(:render_version)
        schedule = create(:schedule, render_version:, recurrence: "daily", status: "paused")
        schedule_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched")
        social_destination = create(:social_destination)
        publication = create(
          :publication,
          render_version:,
          social_destination:,
          schedule_occurrence:,
          status: "approved"
        )
        workflow_run = create(
          :workflow_run,
          workflowable: publication,
          operation: "publication_publish",
          stage: "publish",
          status: "queued"
        )
        service = described_class.new(workflow_run_id: workflow_run.id, worker_id: "publisher-paused")

        expect { service.call }.not_to change(PublicationQuotaReservation, :count)

        expect(service.success?).to eq(false)
        expect(workflow_run.reload.status).to eq("failed")
        expect(publication.reload.status).to eq("draft")
        expect(publication.safe_error_code).to eq("schedule_paused")
        expect(schedule_occurrence.reload.status).to eq("skipped")
      end
    end

    context "when the user explicitly confirms a scheduled Publication while its Schedule is paused" do
      it "returns a claim for that manual review without resuming the Schedule" do
        render_version = create(:render_version)
        schedule = create(:schedule, render_version:, recurrence: "daily", status: "paused")
        schedule_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched")
        publication = create(
          :publication,
          render_version:,
          schedule_occurrence:,
          status: "approved"
        )
        workflow_run = create(
          :workflow_run,
          workflowable: publication,
          operation: "publication_publish",
          stage: "publish",
          status: "queued",
          checkpoint: { "scheduled_manual_confirmation_at" => Time.current.iso8601 }
        )
        service = described_class.new(workflow_run_id: workflow_run.id, worker_id: "manual-review")

        expect { service.call }.to change(PublicationQuotaReservation, :count).by(1)

        expect(service.success?).to eq(true)
        expect(workflow_run.reload.status).to eq("running")
        expect(publication.reload.status).to eq("approved")
        expect(schedule.reload.status).to eq("paused")
        expect(schedule_occurrence.reload.status).to eq("dispatched")
      end
    end
  end
end
