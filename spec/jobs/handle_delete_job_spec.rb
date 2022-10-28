# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HandleDeleteJob, type: :job do
  include ActiveJob::TestHelper

  let(:handle) { HandleNet::FULCRUM_HANDLE_PREFIX + 'validnoid' }

  describe 'job queue' do
    subject(:job) { described_class.perform_later(handle) }

    after do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'queues the job' do
      expect { job }.to have_enqueued_job(described_class).with(handle).on_queue("default")
    end

    it 'executes perform' do
      perform_enqueued_jobs { job }
    end
  end

  context 'job' do
    let(:job) { described_class.new }

    describe '#perform' do
      subject { job.perform(handle) }

      let(:logger) { instance_double(ActiveSupport::Logger, 'logger') }
      let(:record) { instance_double(HandleDeposit, 'record') }
      let(:boolean) { double('boolean') }

      before do
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:error).with("HandleDeleteJob #{handle} StandardError")
        allow(HandleDeposit).to receive(:find_or_create_by).with(handle: handle).and_return(record)
        allow(record).to receive(:action=).with('delete')
        allow(record).to receive(:verified=).with(false)
        allow(record).to receive(:save!)
        allow(HandleNet).to receive(:delete).with(handle).and_return(boolean)
      end

      it 'returns create handle' do
        is_expected.to be boolean
        expect(HandleDeposit).to have_received(:find_or_create_by).with(handle: handle)
        expect(record).to have_received(:action=).with('delete')
        expect(record).to have_received(:verified=).with(false)
        expect(record).to have_received(:save!)
        expect(logger).not_to have_received(:error).with("HandleDeleteJob #{handle} StandardError")
      end

      context 'when standard error' do
        before { allow(HandleNet).to receive(:delete).with(handle).and_raise(StandardError) }

        it 'logs error' do
          is_expected.to be false
          expect(HandleDeposit).to have_received(:find_or_create_by).with(handle: handle)
          expect(record).to have_received(:action=).with('delete')
          expect(record).to have_received(:verified=).with(false)
          expect(record).to have_received(:save!)
          expect(logger).to have_received(:error).with("HandleDeleteJob #{handle} StandardError")
        end
      end
    end
  end
end
