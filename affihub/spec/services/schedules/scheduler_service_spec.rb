require "rails_helper"

RSpec.describe Schedules::SchedulerService, type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "returns success after processing due occurrences" do
      scheduled_at = 10.minutes.ago
      due_occurrence = create(
        :schedule_occurrence,
        occurrence_key: "due-#{SecureRandom.uuid}",
        scheduled_at:,
        dispatch_at: scheduled_at + 5.minutes
      )
      future_scheduled_at = 1.hour.from_now
      future_occurrence = create(
        :schedule_occurrence,
        occurrence_key: "future-#{SecureRandom.uuid}",
        scheduled_at: future_scheduled_at,
        dispatch_at: future_scheduled_at + 5.minutes
      )
      occurrence_processor = double("occurrence processor", call: true)
      allow(Schedules::ProcessOccurrenceService).to receive(:new)
        .with(schedule_occurrence_id: due_occurrence.id)
        .and_return(occurrence_processor)
      service = described_class.new

      expect(service.call).to eq(true)

      expect(Schedules::ProcessOccurrenceService).to have_received(:new).once
      expect(occurrence_processor).to have_received(:call).once
      expect(future_occurrence.reload.status).to eq("scheduled")
    end

    it "returns a queued publication workflow to the queue after an enqueue gap" do
      publication = create(:publication)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      service = described_class.new

      expect { service.call }.to have_enqueued_job(Publications::PublishJob)
        .with(workflow_run.id)
        .exactly(1).times

      expect(service.success?).to eq(true)
    end

    it "returns success without enqueuing queued Publication workflows while auto-publish is paused" do
      automation_control = AutomationControl.current
      automation_control.update!(auto_publish_paused: true)
      publication = create(:publication, schedule_occurrence: create(:schedule_occurrence))
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      service = described_class.new

      expect { service.call }.not_to have_enqueued_job(Publications::PublishJob)

      expect(service.success?).to eq(true)
      expect(workflow_run.reload.status).to eq("queued")
    end

    it "returns without queuing non-publication workflows" do
      workflow_run = create(:workflow_run, status: "queued")
      service = described_class.new

      expect { service.call }.not_to have_enqueued_job(Publications::PublishJob)

      expect(service.success?).to eq(true)
      expect(workflow_run.reload.status).to eq("queued")
    end
  end
end
