# frozen_string_literal: true

require 'rails_helper'
require 'fakefs/spec_helpers'

# This is stolen from Hyrax so we'll periodically keep the spec updated with the Hyrax one, with our own additional...
# specs following, as commented below

describe CharacterizeJob, :clean_repo do
  let(:file_set_id) { 'abc12345' }
  let(:filename)    { Rails.root.join('tmp', 'uploads', 'ab', 'c1', '23', '45', 'abc12345', 'picture.png').to_s }
  let(:label) { 'picture.png' }
  let(:title) { ['My User-Entered Title'] }
  let(:file_set) do
    FileSet.new(id: file_set_id, title: title, label: label, date_modified: 'old_mod_date').tap do |fs|
      allow(fs).to receive(:original_file).and_return(file)
      allow(fs).to receive(:update_index)
    end
  end
  # let(:io)          { JobIoWrapper.new(file_set_id: file_set.id, user: create(:user), path: filename) }
  let(:file) do
    Hydra::PCDM::File.new.tap do |f|
      f.content = 'foo'
      f.original_name = 'picture.png'
      f.height = '111'
      f.width = '222'
      f.file_size = '123456'
      f.format_label = ["Portable Network Graphics"]
      f.original_checksum = ['checksum123']
      f.save!
    end
  end

  before do
    allow(FileSet).to receive(:find).with(file_set_id).and_return(file_set)
    allow(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
    allow(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, filename)
  end

  context 'with valid filepath param' do
    let(:filename) { File.join(fixture_path, 'world.png') }

    it 'skips Hyrax::WorkingDirectory.copy_repository_resource_to_working_directory' do
      expect(Hyrax::WorkingDirectory).not_to receive(:copy_repository_resource_to_working_directory)
      expect(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
      described_class.perform_now(file_set, file.id, filename)
    end
  end

  context 'with no filepath param' do
    let(:filename) { nil }

    it 'uses Hyrax::WorkingDirectory.copy_repository_resource_to_working_directory to pull the repo file' do
      expect(Hyrax::WorkingDirectory).to receive(:copy_repository_resource_to_working_directory)
      expect(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
      described_class.perform_now(file_set, file.id, filename)
    end
  end

  context 'when the characterization proxy content is present' do
    it 'runs Hydra::Works::CharacterizationService and creates a CreateDerivativesJob' do
      expect(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
      expect(file).to receive(:save!)
      expect(file_set).to receive(:update_index)
      expect(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, filename)
      described_class.perform_now(file_set, file.id)
    end
  end

  context 'when the characterization proxy content is absent' do
    before { allow(file_set).to receive(:characterization_proxy?).and_return(false) }
    it 'raises an error' do
      expect { described_class.perform_now(file_set, file.id) }.to raise_error(StandardError, /original_file was not found/)
    end
  end

  context 'FileSet with preexisting characterization metadata getting a new version' do
    before do
      allow(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
      allow(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, filename)
    end

    it 'resets height, width, checksum, file_size and format_label' do
      expect(file).to receive(:save!)
      expect(file_set).to receive(:update_index)
      described_class.perform_now(file_set, file.id)

      expect(file_set.characterization_proxy.height).to eq []
      expect(file_set.original_file.width).to eq []
      expect(file_set.original_file.original_checksum).to eq []
      expect(file_set.original_file.file_size).to eq []
      expect(file_set.original_file.format_label).to eq []
      expect(file_set.label).to eq 'picture.png'
    end

    describe 'title and label' do
      before do
        allow(file_set).to receive(:characterization_proxy).and_call_original
      end

      context 'title and label were previously the same' do
        let(:title) { ['old_filename.jpg'] }
        let(:label) { 'old_filename.jpg' }

        before do
          allow(file_set).to receive_message_chain(:characterization_proxy, :original_name)
                                 .and_return(String.new('new_filename.jpg', encoding: 'ASCII-8BIT')) # rubocop:disable RSpec/MessageChain
        end

        it 'sets title to label' do
          expect(file).to receive(:save!)
          expect(file_set).to receive(:update_index)
          described_class.perform_now(file_set, file.id)
          expect(file_set.title).to eq ['new_filename.jpg']
          expect(file_set.label).to eq 'new_filename.jpg'
        end

        # https://github.com/samvera/hyrax/issues/5671
        context 'original_name, which has encoding set to ASCII-8BIT, contains non-ASCII characters' do
          before do
            allow(file_set).to receive_message_chain(:characterization_proxy, :original_name)
                                   .and_return(String.new('ファイル.txt', encoding: 'ASCII-8BIT')) # rubocop:disable RSpec/MessageChain
          end

          it 'does not raise an error, and still sets title to label' do
            expect(file).to receive(:save!)
            expect(file_set).to receive(:update_index)
            expect { described_class.perform_now(file_set, file.id) }
                .not_to raise_error(Encoding::UndefinedConversionError, '"\xE3" from ASCII-8BIT to UTF-8')
            expect(file_set.title).to eq ['ファイル.txt']
            expect(file_set.label).to eq 'ファイル.txt'
          end
        end
      end

      context 'title and label were not previously the same' do
        let(:title) { ['My User-Entered Title'] }
        let(:label) { 'old_filename.jpg' }

        before do
          allow(file_set).to receive_message_chain(:characterization_proxy, :original_name)
                                 .and_return(String.new('new_filename.jpg', encoding: 'ASCII-8BIT')) # rubocop:disable RSpec/MessageChain
        end

        it 'assumes a user-entered title value and leaves title as-is' do
          expect(file).to receive(:save!)
          expect(file_set).to receive(:update_index)
          described_class.perform_now(file_set, file.id)
          expect(file_set.title).to eq ['My User-Entered Title']
          expect(file_set.label).to eq 'new_filename.jpg'
        end

        # https://github.com/samvera/hyrax/issues/5671
        context 'original_name, which has encoding set to ASCII-8BIT, contains non-ASCII characters' do
          before do
            allow(file_set).to receive_message_chain(:characterization_proxy, :original_name)
                                 .and_return(String.new('ファイル.txt', encoding: 'ASCII-8BIT')) # rubocop:disable RSpec/MessageChain
          end

          it 'does not raise an error, and still sets title to label' do
            expect(file).to receive(:save!)
            expect(file_set).to receive(:update_index)
            expect { described_class.perform_now(file_set, file.id) }
              .not_to raise_error(Encoding::UndefinedConversionError, '"\xE3" from ASCII-8BIT to UTF-8')
            expect(file_set.title).to eq ['My User-Entered Title']
            expect(file_set.label).to eq 'ファイル.txt'
          end
        end
      end
    end

    # note the specs here, while still valid, are altered from those in Hyrax due to out aliasing of `date_modified`
    describe 'date_modified' do
      before do
        allow(file_set).to receive(:characterization_proxy).and_call_original
        allow(Hyrax::TimeService).to receive(:time_in_utc).and_return('new_mod_date')
        file_set.save
      end

      context 'the new checksum is the same as the previous one' do
        before do
          allow(file_set).to receive_message_chain(:characterization_proxy, :original_checksum).and_return(['old_checksum']) # rubocop:disable RSpec/MessageChain
        end

        it 'leaves it as-is' do
          expect(file).to receive(:save!)
          expect(file_set).to receive(:update_index)
          expect(file_set).not_to receive(:date_modified=)
          described_class.perform_now(file_set, file.id)
        end
      end

      context 'the new checksum is not the same as the previous one' do
        before do
          allow(file_set).to receive_message_chain(:characterization_proxy, :original_checksum).and_return(['old_checksum'], ['new_checksum']) # rubocop:disable RSpec/MessageChain
        end

        it 'sets it to now(), a.k.a. "new_mod_date"' do
          expect(file).to receive(:save!)
          expect(file_set).to receive(:update_index)
          expect(file_set).to receive(:date_modified=)
          described_class.perform_now(file_set, file.id)
        end
      end
    end
  end

  # Heliotrope tests follow

  context "when there's a preexisting IIIF cached file" do
    include FakeFS::SpecHelpers
    let(:cached_file) { Rails.root.join('tmp', 'network_files', Digest::MD5.hexdigest(file_set.original_file.uri.to_s)) }

    it "deletes the cached file" do
      FileUtils.mkdir_p Rails.root.join('tmp', 'network_files')
      FileUtils.touch cached_file
      expect(cached_file.exist?).to be true

      allow(Hydra::Works::CharacterizationService).to receive(:run).with(file, filename)
      allow(file).to receive(:save!)
      allow(file_set).to receive(:update_index)
      allow(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, filename)
      described_class.perform_now(file_set, file.id)

      expect(cached_file.exist?).to be false
    end
  end

  context "featured representative" do
    let(:file_path) { (Rails.root + 'tmp' + 'uploads' + 'ab' + 'c1' + '23' + '45' + 'abc12345' + file_type).to_s }
    let(:file) do
      Hydra::PCDM::File.new.tap do |f|
        f.content = 'foo'
        f.original_name = file_type
        f.save!
      end
    end
    let(:monograph) { build(:monograph, id: 'mono_id', press: 'press') }

    before do
      allow(Hydra::Works::CharacterizationService).to receive(:run).with(file, file_path)
      allow(file).to receive(:save!)
      allow(file_set).to receive(:update_index)
      allow(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, file_path)
      allow(file_set).to receive(:parent).and_return(monograph)
    end

    after { FeaturedRepresentative.destroy_all }

    FeaturedRepresentative::KINDS.each do |kind|
      context kind.to_s do
        let(:file_type) { "file.#{kind}" }

        before { allow(UnpackJob).to receive(:perform_later).and_return(true) }

        it "unpacks some kinds" do
          create(:featured_representative, work_id: monograph.id, file_set_id: file_set.id, kind: kind)
          described_class.perform_now(file_set, file.id)
          case kind
          when 'epub', 'webgl', 'pdf_ebook'
            expect(UnpackJob).to have_received(:perform_later).with(file_set.id, kind)
          else
            expect(UnpackJob).not_to have_received(:perform_later).with(file_set.id, kind)
          end
        end
      end
    end
  end

  context 'resource type' do
    let(:file_path) { (Rails.root + 'tmp' + 'uploads' + 'ab' + 'c1' + '23' + '45' + 'abc12345' + file_type).to_s }
    let(:file_type) { 'file.zip' }
    let(:file) do
      Hydra::PCDM::File.new.tap do |f|
        f.content = 'foo'
        f.original_name = file_type
        f.save!
      end
    end
    let(:monograph) { build(:monograph, id: 'mono_id', press: 'press') }

    before do
      allow(Hydra::Works::CharacterizationService).to receive(:run).with(file, file_path)
      allow(file).to receive(:save!)
      allow(file_set).to receive(:update_index)
      allow(CreateDerivativesJob).to receive(:perform_later).with(file_set, file.id, file_path)
      allow(file_set).to receive(:parent).and_return(monograph)
    end

    %w[interactive\ map map foo].each do |resource_type|
      context resource_type do
        let(:resource_type) { resource_type }

        before { allow(UnpackJob).to receive(:perform_later).and_return(true) }

        it "unpacks some resource types" do
          described_class.perform_now(file_set, file.id)
          case resource_type
          when 'interactive_map'
            expect(UnpackJob).to have_received(:perform_later).with(file_set.id, resource_type)
          when 'map'
            expect(UnpackJob).not_to have_received(:perform_later).with(file_set.id, resource_type)
          else
            expect(UnpackJob).not_to have_received(:perform_later).with(file_set.id, resource_type)
          end
        end
      end
    end
  end
end
