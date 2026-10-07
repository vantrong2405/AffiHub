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
  end
end
