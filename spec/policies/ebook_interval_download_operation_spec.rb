# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EbookIntervalDownloadOperation do
  describe '#allowed?' do
    subject { policy.allowed? }

    let(:policy) { described_class.new(actor, ebook) }
    let(:actor) { Anonymous.new({}) }
    let(:ebook) { instance_double(Sighrax::Ebook, 'ebook', publisher: publisher) }
    let(:publisher) { instance_double(Sighrax::Publisher, 'publisher', interval?: interval) }
    let(:interval) { false }
    let(:can_update) { false }
    let(:accessible_online) { false }
    let(:unrestricted) { false }
    let(:licensed_for_download) { false }

    before do
      allow(policy).to receive(:can?).with(:update).and_return can_update
      allow(policy).to receive(:accessible_online?).and_return accessible_online
      allow(policy).to receive(:unrestricted?).and_return unrestricted
      allow(policy).to receive(:licensed_for?).with(:download).and_return licensed_for_download
    end

    it { is_expected.to be false }

    context 'when publisher interval' do
      let(:interval) { true }

      it { is_expected.to be false }

      # HELIO-4264: you can't download PDF chapters from the Monograph catalog page just because you're an editor.
      context 'when can edit' do
        let(:can_update) { true }

        it { is_expected.to be false }
      end

      context 'when online access' do
        let(:accessible_online) { true }

        it { is_expected.to be false }

        context 'when unrestricted' do
          let(:unrestricted) { true }

          it { is_expected.to be true }
        end

        context 'when licensed for download' do
          let(:licensed_for_download) { true }

          it { is_expected.to be true }
        end
      end
    end

    context 'when can edit' do
      let(:can_update) { true }

      it { is_expected.to be false }
    end

    context 'when online access' do
      let(:accessible_online) { true }

      it { is_expected.to be false }

      context 'when unrestricted' do
        let(:unrestricted) { true }

        it { is_expected.to be false }
      end

      context 'when licensed for download' do
        let(:licensed_for_download) { true }

        it { is_expected.to be false }
      end
    end

    context 'when unrestricted' do
      let(:unrestricted) { true }

      it { is_expected.to be false }
    end

    context 'when licensed for download' do
      let(:licensed_for_download) { true }

      it { is_expected.to be false }
    end
  end
end
