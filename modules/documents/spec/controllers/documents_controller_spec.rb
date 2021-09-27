#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2021 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require File.dirname(__FILE__) + '/../spec_helper'

describe DocumentsController do
  render_views

  let(:admin) { FactoryBot.create(:admin) }
  let(:project) { FactoryBot.create(:project, name: "Test Project") }
  let(:user) { FactoryBot.create(:user) }
  let(:role) { FactoryBot.create(:role, permissions: [:view_documents]) }

  let(:default_category) do
    FactoryBot.create(:document_category, project: project, name: "Default Category")
  end

  let(:document) do
    FactoryBot.create(:document, title: "Sample Document", project: project, category: default_category)
  end

  current_user { admin }

  describe "index" do
    let(:long_description) do
      <<-LOREM.strip_heredoc
        Lorem ipsum dolor sit amet, consectetur adipiscing elit.\
        Ut egestas, mi vehicula varius varius, ipsum massa fermentum orci,\
        eget tristique ante sem vel mi. Nulla facilisi.\
        Donec enim libero, luctus ac sagittis sit amet, vehicula sagittis magna.\
        Duis ultrices molestie ante, eget scelerisque sem iaculis vitae.\
        Etiam fermentum mauris vitae metus pharetra condimentum fermentum est pretium.\
        Proin sollicitudin elementum quam quis pharetra.\
        Aenean facilisis nunc quis elit volutpat mollis.\
        Aenean eleifend varius euismod. Ut dolor est, congue eget dapibus eget, elementum eu odio.\
        Integer et lectus neque, nec scelerisque nisi. EndOfLineHere

        Praesent a nunc lorem, ac porttitor eros.
      LOREM
    end

    before do
      document.update(description: long_description)
      get :index, params: { project_id: project.identifier }
    end

    it "should render the index-template successfully" do
      expect(response).to be_successful
      expect(response).to render_template("index")
    end

    it "should group documents by category, if no other sorting is given " do
      expect(assigns(:grouped)).not_to be_nil
      expect(assigns(:grouped).keys.map(&:name)).to eql [default_category.name]
    end

    it "should render documents with long descriptions properly" do
      expect(response.body).to have_selector('.wiki p', visible: :all)
      expect(response.body).to have_selector('.wiki p', visible: :all, text: (document.description.split("\n").first + '...'))
      expect(response.body).to have_selector('.wiki p', visible: :all, text: /EndOfLineHere.../)
    end
  end

  describe 'new' do
    before do
      get :new, params: { project_id: project.id }
    end

    it 'show the new document form' do
      expect(response).to render_template(partial: 'documents/_form')
    end
  end

  describe "create" do
    let(:document_attributes) do
      FactoryBot.attributes_for(:document, title: "New Document",
                                project_id: project.id,
                                category_id: default_category.id)
    end

    before do
      ActionMailer::Base.deliveries.clear
    end

    it "should create a new document with valid arguments" do
      expect do
        post :create, params: { project_id: project.identifier,
                                document: FactoryBot.attributes_for(:document, title: "New Document",
                                                                    project_id: project.id,
                                                                    category_id: default_category.id) }
      end.to change { Document.count }.by 1
    end

    it "should create a new document with valid arguments" do
      expect do
        post :create,
             params: {
               project_id: project.identifier,
               document: document_attributes
             }
      end.to change { Document.count }.by 1
    end

    describe "with attachments" do
      let(:uncontainered) { FactoryBot.create :attachment, container: nil, author: admin }
      before do
        notify_project = project
        FactoryBot.create(:member, project: notify_project, user: user, roles: [role])

        post :create,
             params: {
               project_id: notify_project.identifier,
               document: FactoryBot.attributes_for(:document, title: "New Document",
                                                   project_id: notify_project.id,
                                                   category_id: default_category.id),
               attachments: { '1' => { id: uncontainered.id } }
             }
      end

      it "should add an attachment" do
        document = Document.last

        expect(document.attachments.count).to eql 1
        attachment = document.attachments.first
        expect(uncontainered.reload).to eql attachment
      end

      it "should redirect to the documents-page" do
        expect(response).to redirect_to project_documents_path(project.identifier)
      end
    end
  end

  describe 'show' do
    before do
      document
      get :show, params: { id: document.id }
    end

    it "should delete the document and redirect back to documents-page of the project" do
      expect(response).to be_successful
      expect(response).to render_template('show')
    end
  end

  describe '#add_attachment' do
    let(:recipient) { nil }
    let(:uncontainered) { FactoryBot.create :attachment, container: nil, author: admin }

    before do
      allow(DocumentsMailer)
        .to receive(:attachments_added)
              .and_call_original

      recipient
      document

      post :add_attachment,
           params: {
             id: document.id,
             attachments: { '1' => { id: uncontainered.id } }
           }
    end

    it "should add the attachment" do
      expect(response).to be_redirect
      document.reload
      expect(document.attachments.length).to eq(1)
      expect(uncontainered.reload).to eq document.attachments.first
    end

    it 'should not trigger a mail for the current user' do
      expect(DocumentsMailer)
        .not_to have_received(:attachments_added)
                  .with(current_user, *any_args)
    end

    context 'with a user that does not want to be notified' do
      let!(:recipient) do
        FactoryBot.create :user,
                          member_in_project: project,
                          notification_settings: [
                            FactoryBot.build(:mail_notification_setting,
                                             NotificationSetting::DOCUMENT_ADDED => false)
                          ]
      end

      it 'does not trigger an attachment job' do
        expect(DocumentsMailer)
          .not_to have_received(:attachments_added)
                .with(recipient, *any_args)
      end
    end

    context 'with a user the document is not visible for' do
      let!(:recipient) do
        FactoryBot.create :user,
                          notification_settings: [
                            FactoryBot.build(:mail_notification_setting,
                                             NotificationSetting::DOCUMENT_ADDED => true)
                          ]
      end

      it 'does not trigger an attachment job' do
        expect(DocumentsMailer)
          .not_to have_received(:attachments_added)
                .with(recipient, *any_args)
      end
    end

    context 'with a user that wants to be notified' do
      let!(:recipient) do
        FactoryBot.create :user,
                          member_in_project: project,
                          member_with_permissions: %i[view_documents],
                          notification_settings: [
                            FactoryBot.build(:mail_notification_setting,
                                             NotificationSetting::DOCUMENT_ADDED => true)
                          ]
      end

      it 'does trigger an attachment job' do
        expect(DocumentsMailer)
          .to have_received(:attachments_added)
                .with(recipient, *any_args)
      end
    end
  end

  describe "destroy" do
    before do
      document
    end

    it "should delete the document and redirect back to documents-page of the project" do
      expect do
        delete :destroy, params: { id: document.id }
      end.to change { Document.count }.by -1

      expect(response).to redirect_to "/projects/#{project.identifier}/documents"
      expect { Document.find(document.id) }.to raise_error ActiveRecord::RecordNotFound
    end
  end

  def file_attachment
    test_document = "#{OpenProject::Documents::Engine.root}/spec/assets/attachments/testfile.txt"
    Rack::Test::UploadedFile.new(test_document, "text/plain")
  end
end
