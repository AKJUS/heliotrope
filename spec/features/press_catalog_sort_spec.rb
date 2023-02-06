# frozen_string_literal: true

require 'rails_helper'

describe 'Press catalog sort' do
  let(:title_selector) { '.document .caption h3.index_title' }
  let(:author_selector) { '.document .caption p.authors' }

  context 'Monograph results set end-to-end' do
    before do
      create(:press, subdomain: 'sortpress1')

      # note the `sleep 1` values below are because the sortable date values (date_uploaded create_date) end up...
      # truncated to seconds only in Solr.
      create(:public_monograph,
             press: 'sortpress1',
             title: ['silverfish'],
             creator: ["Hopeful, Barry"],
             date_created: ['20180101'])
      sleep 1
      create(:public_monograph,
             press: 'sortpress1',
             title: ['Cormorant'],
             creator: ['Zidane, "Headbutt"'],
             date_created: ['2015-01-01T00:00'])
      sleep 1
      create(:public_monograph,
             press: 'sortpress1',
             title: ['Zebra'],
             creator: ["Andrée, Renée"],
             date_created: ['2013MMDD'])
      sleep 1
      create(:public_monograph,
             press: 'sortpress1',
             title: ['aardvark'],
             creator: ["Andrea, Rita"],
             date_created: ['2017'])
      sleep 1
      create(:public_monograph,
             press: 'sortpress1',
             title: ['Manatee'],
             creator: ["Gulliver, Guy"],
             date_created: ['2016/05/05'])
      sleep 1
      create(:public_monograph,
             press: 'sortpress1',
             title: ['baboon'],
             creator: ["andrew, ruth"],
             date_created: ['2014'])

      visit "/sortpress1"
    end

    it 'is sortable by "Publication Date (Newest First) by default"' do
      # using corresponding titles to check position as pub year isn't shown in results page (or set here)
      assert_equal page.all(title_selector).map(&:text), ['silverfish',
                                                          'aardvark',
                                                          'Manatee',
                                                          'Cormorant',
                                                          'baboon',
                                                          'Zebra']
    end

    it 'is sortable by "Publication Date (Oldest First)"' do
      click_link 'Publication Date (Oldest First)'
      # using corresponding titles to check position as pub year isn't shown in results page (or set here)
      assert_equal page.all(title_selector).map(&:text), ['Zebra',
                                                          'baboon',
                                                          'Cormorant',
                                                          'Manatee',
                                                          'aardvark',
                                                          'silverfish']
    end

    it 'is sortable by "Date Added (Newest First)"' do
      click_link 'Date Added (Newest First)'
      assert_equal page.all(title_selector).map(&:text), ["baboon",
                                                          "Manatee",
                                                          "aardvark",
                                                          "Zebra",
                                                          "Cormorant",
                                                          "silverfish"]
    end

    it 'is sortable by "Author (A-Z)"' do
      click_link 'Author (A-Z)'
      # names reversed by `authors` method in MonographPresenter
      assert_equal page.all(author_selector).map(&:text), ['Rita Andrea',
                                                           'Renée Andrée',
                                                           'ruth andrew',
                                                           'Guy Gulliver',
                                                           'Barry Hopeful',
                                                           '"Headbutt" Zidane']
    end

    it 'is sortable by "Author (Z-A)"' do
      click_link 'Author (Z-A)'
      # names reversed by `authors` method in MonographPresenter
      assert_equal page.all(author_selector).map(&:text), ['"Headbutt" Zidane',
                                                           'Barry Hopeful',
                                                           'Guy Gulliver',
                                                           'ruth andrew',
                                                           'Renée Andrée',
                                                           'Rita Andrea']
    end

    it 'is sortable by "Title (A-Z)"' do
      click_link 'Title (A-Z)'
      assert_equal page.all(title_selector).map(&:text), ['aardvark',
                                                          'baboon',
                                                          'Cormorant',
                                                          'Manatee',
                                                          'silverfish',
                                                          'Zebra']
    end

    it 'is sortable by "Title (Z-A)"' do
      click_link 'Title (Z-A)'
      assert_equal page.all(title_selector).map(&:text), ['Zebra',
                                                          'silverfish',
                                                          'Manatee',
                                                          'Cormorant',
                                                          'baboon',
                                                          'aardvark']
    end
  end

  context 'Sort by Publication Date tie-break' do
    before do
      create(:press, subdomain: 'sortpress2')

      create(:public_monograph,
             press: 'sortpress2',
             title: ['Date Published Tie-Break Test 1'],
             date_uploaded: DateTime.new(2018, 7, 3, 4, 5, 0, '+0'),
             creator: ['blah'],
             date_created: ['2010'])

      create(:public_monograph,
             press: 'sortpress2',
             title: ['Date Published Tie-Break Test 2'],
             date_uploaded: DateTime.new(2018, 8, 3, 4, 5, 0, '+0'),
             creator: ['blah'],
             date_created: ['2014/01/01'], # only the first 4 digits (YYYY) will have any effect on primary sort
             date_published: [DateTime.new(2019, 12, 16, 4, 3, 0, '+0')])

      create(:public_monograph,
             press: 'sortpress2',
             title: ['Date Published Tie-Break Test 3'],
             date_uploaded: DateTime.new(2018, 9, 3, 4, 5, 0, '+0'),
             creator: ['blah'],
             date_created: ['2014'],
             date_published: [DateTime.new(2019, 12, 16, 4, 2, 0, '+0')])

      create(:public_monograph,
             press: 'sortpress2',
             title: ['Date Published Tie-Break Test 4'],
             date_uploaded: DateTime.new(2018, 10, 3, 4, 5, 0, '+0'),
             creator: ['blah'],
             date_created: ['2014/12/12'], # only the first 4 digits (YYYY) will have any effect on primary sort
             date_published: [DateTime.new(2019, 12, 16, 4, 1, 0, '+0')])

      create(:public_monograph,
             press: 'sortpress2',
             title: ['Date Published Tie-Break Test 5'],
             date_uploaded: DateTime.new(2018, 11, 3, 4, 5, 0, '+0'),
             creator: ['blah'],
             date_created: ['2016/05/05'])

      visit "/sortpress2"
    end

    it 'uses date_published to tie-break the default sort of "Publication Date (Newest First)"' do
      assert_equal page.all(title_selector).map(&:text), ['Date Published Tie-Break Test 5',
                                                          'Date Published Tie-Break Test 2',
                                                          'Date Published Tie-Break Test 3',
                                                          'Date Published Tie-Break Test 4',
                                                          'Date Published Tie-Break Test 1']
    end

    it 'uses date_published to tie-break "Publication Date (Oldest First)"' do
      click_link 'Publication Date (Oldest First)'
      assert_equal page.all(title_selector).map(&:text), ['Date Published Tie-Break Test 1',
                                                          'Date Published Tie-Break Test 4',
                                                          'Date Published Tie-Break Test 3',
                                                          'Date Published Tie-Break Test 2',
                                                          'Date Published Tie-Break Test 5']
    end
  end

  context 'Monograph results set using Solr Docs' do
    # note: The spec above is more appropriate as it incorporates manipulation being done in indexer/presenter, like...
    # sort normalization. I'm doing this additional pure-Solr test for fun, but also because:
    # - if we ever need to test sorting on immutable Fedora values like system_create or system_modified they can be tested in this manner also
    # - it's an excuse to experiment with the minimum Solr fields required by these Blacklight views

    let(:mono_doc_1) {
      ::SolrDocument.new(
        # note: the use of dynamicField in schema.xml takes care of field configuration like cardinality (multiValued)
        # need these 4 fields to get this doc to show on catalog page
        id: '111111111',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        # inexact dynamicField usage summary: *_si for sorting, *_tesim for display, *_dtsi for sortable date
        # note: you can never sort by multi-valued Solr fields, e.g. with an 'm' in the suffix per schema.xml
        title_tesim: 'silverfish',
        title_si: 'silverfish',
        creator_tesim: ['Thomas, John'],
        creator_full_name_si: 'Thomas, John',
        date_created_si: '201516', # sortable publication year, stripped of non-numeric characters (say, 'c.2015-16?')
        date_uploaded_dtsi: '2001-02-25T15:59:47Z' # default sort field
      )
    }
    let(:mono_doc_2) {
      ::SolrDocument.new(
        id: '222222222',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        title_tesim: 'Cormorant',
        title_si: 'cormorant', # this is downcased on indexing, otherwise sort will have caps first
        creator_tesim: 'Hopeful, Barry',
        creator_full_name_si: 'Hopeful, Barry',
        date_created_si: '2012-02-21T17:03:54Z', # terrible publication year entry, should still alpha sort OK
        date_uploaded_dtsi: '1999-01-25T15:59:47Z'
      )
    }
    let(:mono_doc_3) {
      ::SolrDocument.new(
        id: '333333333',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        title_tesim: 'Zebra',
        title_si: 'zebra', # this is downcased on indexing, otherwise sort will have caps first
        creator_tesim: 'Quinn, Smiley',
        creator_full_name_si: 'Quinn, Smiley',
        date_created_si: '2014',
        date_uploaded_dtsi: '2011-06-25T15:59:47Z'
      )
    }
    let(:mono_doc_4) {
      ::SolrDocument.new(
        id: '444444444',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        title_tesim: 'aardvark',
        title_si: 'aardvark',
        creator_tesim: 'Gulliver, Guy',
        creator_full_name_si: 'Gulliver, Guy',
        date_created_si: '2013?',
        date_uploaded_dtsi: '2018-03-25T15:59:47Z'
      )
    }
    let(:mono_doc_5) {
      ::SolrDocument.new(
        id: '555555555',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        title_tesim: 'Manatee',
        title_si: 'manatee', # this is downcased on indexing, otherwise sort will have caps first
        creator_tesim: 'Rodrigues, Maria',
        creator_full_name_si: 'Rodrigues, Maria',
        date_created_si: 'c2016',
        date_uploaded_dtsi: '2017-04-25T15:59:47Z'
      )
    }
    let(:mono_doc_6) {
      ::SolrDocument.new(
        id: '666666666',
        has_model_ssim: 'Monograph',
        press_sim: "sortpress3",
        read_access_group_ssim: "public",
        title_tesim: 'baboon',
        title_si: 'baboon',
        creator_tesim: 'Smith, Jim',
        creator_full_name_si: 'Smith, Jim',
        date_created_si: '2011',
        date_uploaded_dtsi: '2014-05-25T15:59:47Z'
      )
    }

    before do
      create(:press, subdomain: 'sortpress3')
      ActiveFedora::SolrService.add([mono_doc_1.to_h,
                                     mono_doc_2.to_h,
                                     mono_doc_3.to_h,
                                     mono_doc_4.to_h,
                                     mono_doc_5.to_h,
                                     mono_doc_6.to_h])
      ActiveFedora::SolrService.commit
      visit "/sortpress3"
    end

    it 'is sorted by "Publication Date (Newest First)" by default' do
      # using corresponding titles to check position as pub year isn't shown in results page (or set here)
      assert_equal page.all(title_selector).map(&:text), ['Manatee',
                                                          'silverfish',
                                                          'Zebra',
                                                          'aardvark',
                                                          'Cormorant',
                                                          'baboon']
    end

    it 'is sortable by "Publication Date (Oldest First)"' do
      click_link 'Publication Date (Oldest First)'
      # using corresponding titles to check position as pub year isn't shown in results page (or set here)
      assert_equal page.all(title_selector).map(&:text), ['baboon',
                                                          'Cormorant',
                                                          'aardvark',
                                                          'Zebra',
                                                          'silverfish',
                                                          'Manatee']
    end

    it 'is sortable by "Date Added (Newest First)"' do
      click_link 'Date Added (Newest First)'
      assert_equal page.all(title_selector).map(&:text), ['aardvark',
                                                          'Manatee',
                                                          'baboon',
                                                          'Zebra',
                                                          'silverfish',
                                                          'Cormorant']
    end

    it 'is sortable by "Author (A-Z)"' do
      click_link 'Author (A-Z)'
      # names reversed by `authors` method in MonographPresenter
      assert_equal page.all(author_selector).map(&:text), ['Guy Gulliver',
                                                           'Barry Hopeful',
                                                           'Smiley Quinn',
                                                           'Maria Rodrigues',
                                                           'Jim Smith',
                                                           'John Thomas']
    end

    it 'is sortable by "Author (Z-A)"' do
      click_link 'Author (Z-A)'
      # names reversed by `authors` method in MonographPresenter
      assert_equal page.all(author_selector).map(&:text), ['John Thomas',
                                                           'Jim Smith',
                                                           'Maria Rodrigues',
                                                           'Smiley Quinn',
                                                           'Barry Hopeful',
                                                           'Guy Gulliver']
    end

    it 'is sortable by "Title (A-Z)"' do
      click_link 'Title (A-Z)'
      assert_equal page.all(title_selector).map(&:text), ['aardvark',
                                                          'baboon',
                                                          'Cormorant',
                                                          'Manatee',
                                                          'silverfish',
                                                          'Zebra']
    end

    it 'is sortable by "Title (Z-A)"' do
      click_link 'Title (Z-A)'
      assert_equal page.all(title_selector).map(&:text), ['Zebra',
                                                          'silverfish',
                                                          'Manatee',
                                                          'Cormorant',
                                                          'baboon',
                                                          'aardvark']
    end
  end
end
