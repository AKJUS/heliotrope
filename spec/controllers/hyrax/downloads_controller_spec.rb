# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Hyrax::DownloadsController, type: :controller do
  let(:user) { create(:user) }

  describe "#show" do
    context "when allow_download is yes" do
      let(:file_set) {
        create(:file_set,
               user: user,
               allow_download: 'yes',
               read_groups: ["public"],
               content: File.open(File.join(fixture_path, 'csv', 'miranda.jpg')))
      }

      context "and a user is logged in" do
        before { sign_in user }

        it "sends the file" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response.body).to eq file_set.original_file.content
        end
      end

      context "and the user is not logged in" do
        it "sends the file" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response.body).to eq file_set.original_file.content
        end
      end

      context "triggers counter reporting, internally and for irus" do
        let(:press) { create(:press) }
        let(:monograph) { create(:monograph, press: press.subdomain, title: ["A Test"]) }
        let(:counter_service) { double('counter_service') }

        before do
          monograph.ordered_members << file_set
          monograph.save!
          file_set.save!
          allow(CounterService).to receive(:from).and_return(counter_service)
          allow(counter_service).to receive(:count)
        end

        it "counts" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(counter_service).to have_received(:count)
          expect(response.body).to eq file_set.original_file.content
        end
      end

      context "if the file is a pdf_ebook that needs watermarking" do
        let(:press) { create(:press, watermark: true) }
        let(:monograph) { create(:monograph, press: press.subdomain, title: ["A Test"]) }

        before do
          monograph.ordered_members << file_set
          monograph.save!
          file_set.save!
          FeaturedRepresentative.create(work_id: monograph.id, file_set_id: file_set.id, kind: "pdf_ebook")
        end

        context "and a user is logged in and privledged" do
          let(:user) { create(:press_admin, press: press) }

          before { sign_in user }

          it "sends the file" do
            get :show, params: { id: file_set.id, use_route: 'downloads' }
            expect(response.body).to eq file_set.original_file.content
          end
        end

        context "and a user logged in and unprivledged" do
          let(:non_edit_user) { create(:user) }

          before { sign_in non_edit_user }

          it "redirects to the watermarked download" do
            get :show, params: { id: file_set.id, use_route: 'downloads' }
            expect(response).to redirect_to(Rails.application.routes.url_helpers.download_ebook_url(file_set.id))
          end
        end

        context "and a user is not logged in" do
          it "redirects to the watermarked download" do
            get :show, params: { id: file_set.id, use_route: 'downloads' }
            expect(response).to redirect_to(Rails.application.routes.url_helpers.download_ebook_url(file_set.id))
          end
        end
      end
    end

    context "when allow_download is not yes" do
      let(:file_set) {
        create(:file_set,
               user: user,
               allow_download: 'no',
               read_groups: ["public"],
               content: File.open(File.join(fixture_path, 'csv', 'miranda.jpg')))
      }

      context "and a non-edit user is logged in" do
        let(:non_edit_user) { create(:user) }

        before { sign_in non_edit_user }

        it "shows the unauthorized message" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response).to have_http_status(:unauthorized)
        end

        context "animated GIF file is downloadable anyway" do
          before { allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:animated_gif?).and_return(true) }

          it "sends the file" do
            get :show, params: { id: file_set.id, use_route: 'downloads' }
            expect(response).to have_http_status(:ok)
            expect(response.body).to eq file_set.original_file.content
          end
        end
      end

      context "and an edit user is logged in" do
        let(:press) { create(:press) }
        let(:user) { create(:press_editor, press: press) }
        let(:monograph) { create(:monograph, press: press.subdomain, title: ["A Test"]) }

        before do
          sign_in user
          monograph.ordered_members << file_set
          monograph.save!
          file_set.save!
        end

        it "sends the file" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq file_set.original_file.content
        end
      end

      context "and the user is not logged in" do
        it "shows the unauthorized message" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response).to have_http_status(:unauthorized)
        end
      end

      context "and the user is logged in as a platform_admin" do
        let(:platform_admin) { create(:platform_admin) }

        before { sign_in platform_admin }

        it "sends the file" do
          get :show, params: { id: file_set.id, use_route: 'downloads' }
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq file_set.original_file.content
        end
      end
    end

    context "jpeg (for use as video poster attribute) derivative" do
      # allow_download is not relevant to derivative behavior
      let(:file_set) { create(:file_set, user: user, allow_download: 'no', read_groups: ['public']) }
      let(:thumbnail_path) { Hyrax::DerivativePath.derivative_path_for_reference(file_set.id, 'thumbnail') }
      # the new 'jpeg' derivative meant for video 'poster' attribute
      let(:jpeg_path) { Hyrax::DerivativePath.derivative_path_for_reference(file_set.id, 'jpeg') }
      let(:thumbnail_file) { File.join(fixture_path, 'csv', 'shipwreck.jpg') }
      let(:jpeg_file) { File.join(fixture_path, 'csv', 'miranda.jpg') }
      let(:derivatives_directory) { File.dirname(thumbnail_path) }

      before do
        FileUtils.mkdir_p(derivatives_directory)
      end

      it "if there is no jpeg derivative, it sends the thumbnail derivative in its stead" do
        # no derivatives for this FileSet yet
        expect(Hyrax::DerivativePath.derivatives_for_reference(file_set).count).to eq 0

        # manually add a thumbnail derivative, check derivative count is 1
        FileUtils.cp(thumbnail_file, thumbnail_path)
        expect(Hyrax::DerivativePath.derivatives_for_reference(file_set).count).to eq 1

        # ask for (missing) jpeg derivative, receive thumbnail instead
        get :show, params: { id: file_set.id, use_route: 'downloads', file: 'jpeg' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq IO.binread(thumbnail_file)
      end
      it "sends the jpeg derivative on request if it exists" do
        # no derivatives for this FileSet yet
        expect(Hyrax::DerivativePath.derivatives_for_reference(file_set).count).to eq 0

        # manually add thumbnail and jpeg derivatives, check derivative count is 2
        FileUtils.cp(thumbnail_file, thumbnail_path)
        FileUtils.cp(jpeg_file, jpeg_path)
        expect(Hyrax::DerivativePath.derivatives_for_reference(file_set).count).to eq 2

        # ask for, and receive, the jpeg derivative
        get :show, params: { id: file_set.id, use_route: 'downloads', file: 'jpeg' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq IO.binread(jpeg_file)
      end
      after do
        FileUtils.rm_rf(Hyrax.config.derivatives_path)
      end
    end

    context "PDF extracted_text download" do
      let(:file_set) {
        create(:file_set,
               user: user,
               allow_download: 'yes',
               read_groups: ["public"])
      }
      let(:text_file) do
        Hydra::PCDM::File.new.tap do |f|
          f.content = IO.read(File.join(fixture_path, 'test_pdf.txt'))
          f.original_name = 'test_pdf.txt'
          f.save!
        end
      end

      let(:mock_association) { double('blah') }

      before do
        allow(subject).to receive(:dereference_file).with(:extracted_text).and_return(mock_association) # rubocop:disable RSpec/SubjectStub
      end

      context "When the extracted_text file exists" do
        before do
          allow(mock_association).to receive(:reader).and_return(text_file)
        end

        it "sends the file given the related URL parameter" do
          get :show, params: { id: file_set.id, file: 'extracted_text', use_route: 'downloads' }
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq IO.read(File.join(fixture_path, 'test_pdf.txt'))
        end
      end

      context "When the extracted_text file does not exist" do
        before do
          allow(mock_association).to receive(:reader).and_return(nil)
        end

        it "returns 401" do
          get :show, params: { id: file_set.id, file: 'extracted_text', use_route: 'downloads' }
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'closed caption' do
      # allow_download is not relevant to closed caption
      let(:file_set) { create(:public_file_set, user: user, allow_download: 'no', read_groups: ['public'], closed_captions: [closed_captions]) }
      let(:closed_captions) do
        <<~CAPTIONS_VTT
        closed caption a
        closed caption b
        closed caption c
        CAPTIONS_VTT
      end

      it 'downloads closed caption metadata' do
        get :show, params: { id: file_set.id, use_route: 'downloads', file: 'captions_vtt' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq closed_captions
      end
    end

    context 'visual description' do
      # allow_download is not relevant to visual description
      let(:file_set) { create(:public_file_set, user: user, allow_download: 'no', read_groups: ['public'], visual_descriptions: [visual_descriptions]) }
      let(:visual_descriptions) do
        <<~DESCRIPTIONS_VTT
          visual description a
          visual description b
          visual description c
        DESCRIPTIONS_VTT
      end

      it 'downloads visual description metadata' do
        get :show, params: { id: file_set.id, use_route: 'downloads', file: 'descriptions_vtt' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq visual_descriptions
      end
    end

    context 'embed_css' do
      context 'responsive embed codes' do
        let(:file_set) { create(:public_file_set, user: user, read_groups: ['public']) }
        # Note that padding-bottom defaults to 60%, giving a 5:3 ratio when width and height values are not available.
        # Similarly, max-width defaults to 400px.
        # The varying padding values are thoroughly exercised in spec/presenters/concerns/embed_code_presenter_spec.rb
        let(:embed_css) do
          <<~EMBED_CSS
              #fulcrum-embed-outer-#{file_set.id} {
                width:auto;
                page-break-inside:avoid;
                -webkit-column-break-inside:avoid;
                break-inside:avoid;
                max-width:1000px;
                margin:auto;
                background-color:#000;
              }
              #fulcrum-embed-inner-#{file_set.id} {
                overflow:hidden;
                padding-bottom:60%;
                position:relative; height:0;
              }
              iframe#fulcrum-embed-iframe-#{file_set.id} {
                overflow:hidden;
                border-width:0;
                left:0; top:0;
                width:100%;
                height:100%;
                position:absolute;
              }
          EMBED_CSS
        end

        context 'FileSet is an image' do
          before { allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:image?).and_return(true) }

          it 'downloads a css file' do
            get :show, params: { id: file_set.id, use_route: 'downloads', file: 'embed_css' }
            expect(response).to have_http_status(:ok)
            expect(response.content_type).to eq('text/css')
            expect(response.body).to eq embed_css
          end
        end

        context 'FileSet is a video' do
          before { allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:interactive_map?).and_return(true) }

          it 'downloads a css file' do
            get :show, params: { id: file_set.id, use_route: 'downloads', file: 'embed_css' }
            expect(response).to have_http_status(:ok)
            expect(response.content_type).to eq('text/css')
            expect(response.body).to eq embed_css
          end
        end

        context 'FileSet is an interactive map' do
          let(:file_set) { create(:public_file_set, user: user, read_groups: ['public'], resource_type: ['interactive map']) }

          it 'downloads a css file' do
            get :show, params: { id: file_set.id, use_route: 'downloads', file: 'embed_css' }
            expect(response).to have_http_status(:ok)
            expect(response.content_type).to eq('text/css')
            expect(response.body).to eq embed_css
          end
        end
      end

      context 'fixed-height embed codes (e.g. audio)' do
        let(:file_set) { create(:public_file_set, user: user, read_groups: ['public']) }
        # Note that heights defaults to 125px for an audio file with no WebVTT and thus no interactive transcript.
        # The varying height values are thoroughly exercised in spec/presenters/concerns/embed_code_presenter_spec.rb
        let(:embed_css) do
          <<~EMBED_CSS
              #fulcrum-embed-outer-#{file_set.id} {
              }
              #fulcrum-embed-inner-#{file_set.id} {
              }
              iframe#fulcrum-embed-iframe-#{file_set.id} {
                page-break-inside:avoid;
                -webkit-column-break-inside:avoid;
                break-inside:avoid;
                display:block;
                overflow:hidden;
                border-width:0;
                width:98%;
                max-width:98%;
                height:125px;
                margin:auto;
              }
          EMBED_CSS
        end

        context 'FileSet is an audio file' do
          before { allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:audio?).and_return(true) }

          it 'downloads a css file' do
            get :show, params: { id: file_set.id, use_route: 'downloads', file: 'embed_css' }
            expect(response).to have_http_status(:ok)
            expect(response.content_type).to eq('text/css')
            expect(response.body).to eq embed_css
          end
        end
      end
    end

    context "share links for derivative files" do
      let(:monograph) { create(:monograph) }

      let(:published_resource_file_set) {
        create(:file_set,
               allow_download: 'no',
               visibility: 'open',
               content: File.open(File.join(fixture_path, 'it.mp4')))
      }

      let(:draft_resource_file_set) {
        create(:file_set,
               allow_download: 'no',
               visibility: 'restricted',
               content: File.open(File.join(fixture_path, 'it.mp4')))
      }

      let(:draft_closed_captions_file_set) {
        create(:file_set,
               allow_download: 'no',
               visibility: 'restricted')
      }

      let(:draft_visual_descriptions_file_set) {
        create(:file_set,
               allow_download: 'no',
               visibility: 'restricted')
      }

      let(:draft_epub_file_set) {
        create(:file_set,
               allow_download: 'no',
               visibility: 'restricted',
               content: File.open(File.join(fixture_path, 'fake_epub01.epub')))
      }

      let(:valid_share_token) do
        JsonWebToken.encode(data: monograph.id, exp: Time.now.to_i + 28 * 24 * 3600)
      end

      before do
        monograph.ordered_members << draft_resource_file_set << draft_epub_file_set << draft_closed_captions_file_set
        monograph.ordered_members << draft_visual_descriptions_file_set << published_resource_file_set
        monograph.save!
        draft_resource_file_set.save!
        draft_epub_file_set.save!
        published_resource_file_set.save!
        FeaturedRepresentative.create(work_id: monograph.id, file_set_id: draft_epub_file_set.id, kind: "epub")

        allow(Hyrax::DerivativePath).to receive(:derivative_path_for_reference).and_call_original
        allow(Hyrax::DerivativePath).to receive(:derivative_path_for_reference)
                                          .with(published_resource_file_set.id, 'mp4')
                                          .and_return(File.join(fixture_path, 'it.mp4'))
        allow(Hyrax::DerivativePath).to receive(:derivative_path_for_reference)
                                          .with(draft_resource_file_set.id, 'mp4')
                                          .and_return(File.join(fixture_path, 'it.mp4'))

        allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:closed_captions).and_return('CLOSED CAPTIONS!!')
        allow_any_instance_of(Hyrax::FileSetPresenter).to receive(:visual_descriptions).and_return('VISUAL DESCRIPTIONS!!!')
      end

      it "the published resource's derivative can be downloaded with no share link" do
        get :show, params: { id: published_resource_file_set.id, use_route: 'downloads', file: 'mp4' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq IO.binread(File.join(fixture_path, 'it.mp4'))
      end

      it "the draft resource's derivative cannot be downloaded with no share link" do
        get :show, params: { id: draft_resource_file_set.id, use_route: 'downloads', file: 'mp4' }
        expect(response).to have_http_status(:unauthorized)
      end

      it "the draft closed_captions cannot be downloaded with no share link" do
        get :show, params: { id: draft_closed_captions_file_set.id, use_route: 'downloads', file: 'captions_vtt' }
        expect(response).to have_http_status(:unauthorized)
      end

      it "the draft visual_descriptions cannot be downloaded with no share link" do
        get :show, params: { id: draft_visual_descriptions_file_set.id, use_route: 'downloads', file: 'descriptions_vtt' }
        expect(response).to have_http_status(:unauthorized)
      end

      it "the draft resource's derivative can be downloaded with its monograph's EPUB share link" do
        get :show, params: { id: draft_resource_file_set.id, use_route: 'downloads', file: 'mp4', share: valid_share_token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq IO.binread(File.join(fixture_path, 'it.mp4'))
      end

      it "the draft closed_captions can be downloaded with its monograph's EPUB share link" do
        get :show, params: { id: draft_closed_captions_file_set.id, use_route: 'downloads', file: 'captions_vtt', share: valid_share_token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq 'CLOSED CAPTIONS!!'
      end

      it "the draft visual_descriptions can be downloaded with its monograph's EPUB share link" do
        get :show, params: { id: draft_visual_descriptions_file_set.id, use_route: 'downloads', file: 'descriptions_vtt', share: valid_share_token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq 'VISUAL DESCRIPTIONS!!!'
      end
    end
  end

  describe "#mime_type_for" do
    let(:file) { File.join(fixture_path, 'it.mp4') }

    it "gives the correct mime_type for an mp4 video" do
      expect(subject.mime_type_for(file)).to eq('video/mp4')
    end
  end

  describe "allow_download is nil" do
    let(:file_set) {
      create(:file_set,
             user: user,
             content: File.open(File.join(fixture_path, 'csv', 'miranda.jpg')))
    }

    it "does not raise an error when you try to download the file" do
      expect { get :show, params: { id: file_set.id, use_route: 'downloads' } }.not_to raise_error
    end
  end

  describe "#disposition" do
    context "a pdf asset" do
      let(:presenter) { double("presenter", pdf_ebook?: false, file_format: "pdf (Portable Document Format)") }

      it "is inline" do
        expect(subject.disposition(presenter)).to eq "inline"
      end
    end

    context "not a pdf" do
      let(:presenter) { double("presenter", pdf_ebook?: false, file_format: "jpeg (JPEG File Interchange Format, JPEG EXIF)") }

      it "is attachment" do
        expect(subject.disposition(presenter)).to eq "attachment"
      end
    end

    context "a pdf_ebook" do
      # Users shouldn't get here, the file_set show page isn't normally user accessible
      let(:presenter) { double("presenter", pdf_ebook?: true, file_format: "pdf (Portable Document Format)") }

      it "is attachment" do
        expect(subject.disposition(presenter)).to eq "attachment"
      end
    end
  end
end
