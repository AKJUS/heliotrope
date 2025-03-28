# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RecacheInCommonMetadataJob, type: :job do
  include ActiveJob::TestHelper

  describe 'job queue' do
    subject(:job) { described_class.perform_later }

    after do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'queues the job' do
      expect { job }.to have_enqueued_job(described_class).on_queue("default")
    end
  end

  context 'job' do
    let(:job) { described_class.new }

    describe 'perform' do
      subject { job.perform }

      before do
        allow(job).to receive(:download_xml).and_return(true)
        allow(job).to receive(:parse_xml).and_return(true)
        allow(job).to receive(:cache_json).and_return(true)
        allow(job).to receive(:in_common).and_return(true)
      end

      it do
        is_expected.to be true
        expect(job).to have_received(:download_xml)
        expect(job).to have_received(:parse_xml)
        expect(job).to have_received(:cache_json)
        expect(job).to have_received(:in_common)
      end

      context 'fail' do
        context 'in_common' do
          before { allow(job).to receive(:in_common).and_return(false) }

          it do
            is_expected.to be false
            expect(job).to     have_received(:download_xml)
            expect(job).to     have_received(:parse_xml)
            expect(job).to     have_received(:cache_json)
            expect(job).to     have_received(:in_common)
          end

          context 'cache_json' do
            before { allow(job).to receive(:cache_json).and_return(false) }

            it do
              is_expected.to be false
              expect(job).to     have_received(:download_xml)
              expect(job).to     have_received(:parse_xml)
              expect(job).to     have_received(:cache_json)
              expect(job).not_to have_received(:in_common)
            end

            context 'parse_xml' do
              before { allow(job).to receive(:parse_xml).and_return(false) }

              it do
                is_expected.to be false
                expect(job).to     have_received(:download_xml)
                expect(job).to     have_received(:parse_xml)
                expect(job).not_to have_received(:cache_json)
                expect(job).not_to have_received(:in_common)
              end

              context 'download_xml' do
                before { allow(job).to receive(:download_xml).and_return(false) }

                it do
                  is_expected.to be false
                  expect(job).to     have_received(:download_xml)
                  expect(job).not_to have_received(:parse_xml)
                  expect(job).not_to have_received(:cache_json)
                  expect(job).not_to have_received(:in_common)
                end
              end
            end
          end
        end
      end
    end

    describe '#download_xml' do
      context "when both downloads succeed" do
        it "returns true" do
          [RecacheInCommonMetadataJob::INCOMMON_DOWNLOAD_CMD, RecacheInCommonMetadataJob::OPENATHENS_DOWNLOAD_CMD].each do |cmd|
            allow(Open3).to receive(:popen3).with(cmd).and_return(
              [double('stdin', close: true), double('stdout', close: true), double('stderr', close: true, read: ''), double('wait_thr', value: double('process_status', success?: true))]
            )
          end

          expect(described_class.new.download_xml).to be true
        end
      end

      context "when any download fails" do
        it "returns false and logs an error" do
          command = RecacheInCommonMetadataJob::INCOMMON_DOWNLOAD_CMD
          allow(Open3).to receive(:popen3).with(command).and_return(
            [double('stdin', close: true), double('stdout', close: true), double('stderr', close: true, read: 'Some error'), double('wait_thr', value: double('process_status', success?: false))]
          )

          expect(Rails.logger).to receive(:error).with(/ERROR Command #{Regexp.escape(command)} error Some error/)

          expect(described_class.new.download_xml).to be false
        end
      end
    end

    describe '#parse_xml' do
      subject { job.parse_xml }

      context 'no files' do
        before do
          FileUtils.rm(described_class::INCOMMON_XML_FILE) if File.exist?(described_class::INCOMMON_XML_FILE)
          FileUtils.rm(described_class::OPENATHENS_XML_FILE) if File.exist?(described_class::OPENATHENS_XML_FILE)
        end

        it do
          is_expected.to be true
          expect(JSON.load(File.read(described_class::JSON_FILE))).to eq([])
        end
      end

      context 'file' do
        before do
          FileUtils.cp(Rails.root.join('spec', 'fixtures', 'feed', 'InCommon-metadata.xml'), described_class::INCOMMON_XML_FILE)
          FileUtils.cp(Rails.root.join('spec', 'fixtures', 'feed', 'OpenAthens-metadata.xml'), described_class::OPENATHENS_XML_FILE)
        end

        it do
          is_expected.to be true
          expect(FileUtils.compare_file(Rails.root.join('spec', 'fixtures', 'feed', 'federated-shib-metadata.json'), described_class::JSON_FILE)).to be true
        end
      end
    end

    describe '#load_json' do
      subject { job.load_json }

      context 'no file' do
        before { FileUtils.rm(described_class::JSON_FILE) if File.exist?(described_class::JSON_FILE) }

        it { is_expected.to eq([]) }
      end

      context 'file' do
        before { FileUtils.cp(Rails.root.join('spec', 'fixtures', 'feed', 'federated-shib-metadata.json'), described_class::JSON_FILE) }

        it { is_expected.to eq(JSON.load(File.read(Rails.root.join('spec', 'fixtures', 'feed', 'federated-shib-metadata.json')))) }

        context 'standard error' do
          let(:message) { 'ERROR: RecacheInCommonMetadataJob#load_json raised StandardError' }

          before do
            allow(JSON).to receive(:load).and_raise(StandardError)
            allow(Rails.logger).to receive(:error).with(message)
          end

          it do
            is_expected.to eq([])
            expect(Rails.logger).to have_received(:error).with(message)
          end
        end
      end
    end

    describe '#cache_json' do
      subject { job.cache_json }

      let(:loaded_json) { double('loaded_json') }

      before do
        allow(job).to receive(:load_json).and_return(loaded_json)
        allow(Rails.cache).to receive(:write).with(described_class::RAILS_CACHE_KEY, loaded_json, expires_in: 24.hours)
      end

      it do
        is_expected.to be true
        expect(job).to have_received(:load_json)
        expect(Rails.cache).to have_received(:write).with(described_class::RAILS_CACHE_KEY, loaded_json, expires_in: 24.hours)
      end
    end

    describe '#in_common' do
      subject { job.in_common }

      let(:in_common_institution) { instance_double(Greensub::Institution, 'in_common_institution', in_common: false, entity_id: "https://ccbcmd.idm.oclc.org/shibboleth") }
      let(:open_athens_institution) { instance_double(Greensub::Institution, 'open_athens_institution', in_common: false, entity_id: "https://idp.kycad.org/entity") }
      let(:not_in_common_institution) { instance_double(Greensub::Institution, 'not_in_common_institution', in_common: false, entity_id: "https://shibboleth.umich.edu/idp/shibboleth") }

      before do
        allow(Greensub::Institution).to receive(:update_all).with(in_common: false)
        allow(Greensub::Institution).to receive(:where).with("entity_id <> ''").and_return([in_common_institution, open_athens_institution, not_in_common_institution])
        allow(Greensub::Institution).to receive(:where).with(entity_id: "https://ccbcmd.idm.oclc.org/shibboleth").and_return([in_common_institution])
        allow(Greensub::Institution).to receive(:where).with(entity_id: "https://idp.kycad.org/entity").and_return([open_athens_institution])
        allow(Greensub::Institution).to receive(:where).with(entity_id: "https://shibboleth.umich.edu/idp/shibboleth").and_return([not_in_common_institution])
        allow(in_common_institution).to receive(:in_common=).with(true)
        allow(open_athens_institution).to receive(:in_common=).with(true)
        allow(in_common_institution).to receive(:save!)
        allow(open_athens_institution).to receive(:save!)
      end

      context 'no file' do
        before { FileUtils.rm(described_class::JSON_FILE) if File.exist?(described_class::JSON_FILE) }

        it do
          is_expected.to be false
          expect(Greensub::Institution).not_to have_received(:update_all).with(in_common: false)
          expect(Greensub::Institution).not_to have_received(:where).with("entity_id <> ''")
          expect(Greensub::Institution).not_to have_received(:where).with(entity_id: "https://ccbcmd.idm.oclc.org/shibboleth")
          expect(Greensub::Institution).not_to have_received(:where).with(entity_id: "https://idp.kycad.org/entity")
          expect(Greensub::Institution).not_to have_received(:where).with(entity_id: "https://shibboleth.umich.edu/idp/shibboleth")
          expect(in_common_institution).not_to have_received(:in_common=).with(true)
          expect(in_common_institution).not_to have_received(:save!)
          expect(open_athens_institution).not_to have_received(:in_common=).with(true)
          expect(open_athens_institution).not_to have_received(:save!)
        end
      end

      context 'file' do
        before { FileUtils.cp(Rails.root.join('spec', 'fixtures', 'feed', 'federated-shib-metadata.json'), described_class::JSON_FILE) }

        it do
          is_expected.to be true
          expect(Greensub::Institution).to     have_received(:update_all).with(in_common: false)
          expect(Greensub::Institution).to     have_received(:where).with("entity_id <> ''")
          expect(Greensub::Institution).to     have_received(:where).with(entity_id: "https://ccbcmd.idm.oclc.org/shibboleth")
          expect(Greensub::Institution).to     have_received(:where).with(entity_id: "https://idp.kycad.org/entity")
          expect(Greensub::Institution).not_to have_received(:where).with(entity_id: "https://shibboleth.umich.edu/idp/shibboleth")
          expect(in_common_institution).to     have_received(:in_common=).with(true)
          expect(in_common_institution).to     have_received(:save!)
          expect(open_athens_institution).to   have_received(:in_common=).with(true)
          expect(open_athens_institution).to   have_received(:save!)
        end

        # HELIO-4243
        # U of M Ann Arbor, Dearborn and Flint all have the same entity_id, but there's only 1 U of M
        # listed in the inCommon-metadata
        context "more than one in_common institutions with a shared entity_id" do
          let(:other_institution_with_the_same_entity_id) { instance_double(Greensub::Institution, 'other_institution_with_the_same_entity_id', in_common: false, entity_id: "https://ccbcmd.idm.oclc.org/shibboleth") }

          before do
            allow(Greensub::Institution).to receive(:where).with(entity_id: "https://ccbcmd.idm.oclc.org/shibboleth").and_return([in_common_institution, other_institution_with_the_same_entity_id])
            allow(other_institution_with_the_same_entity_id).to receive(:in_common=).with(true)
            allow(other_institution_with_the_same_entity_id).to receive(:save!)
          end

          it "multiple institutions get in_common=true if their entity_id is in InCommon-metadata" do
            is_expected.to be true
            expect(Greensub::Institution).to     have_received(:update_all).with(in_common: false)
            expect(Greensub::Institution).to     have_received(:where).with("entity_id <> ''")
            expect(Greensub::Institution).to     have_received(:where).with(entity_id: "https://ccbcmd.idm.oclc.org/shibboleth")
            expect(Greensub::Institution).not_to have_received(:where).with(entity_id: "https://shibboleth.umich.edu/idp/shibboleth")
            expect(in_common_institution).to     have_received(:in_common=).with(true)
            expect(in_common_institution).to     have_received(:save!)
            expect(other_institution_with_the_same_entity_id).to have_received(:in_common=).with(true)
            expect(other_institution_with_the_same_entity_id).to have_received(:save!)
          end
        end
      end
    end
  end
end
