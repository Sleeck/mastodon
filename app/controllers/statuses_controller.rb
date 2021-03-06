# frozen_string_literal: true

class StatusesController < ApplicationController
  include StatusControllerConcern
  include SignatureAuthentication
  include Authorization
  include AccountOwnedConcern

  layout 'public'

  before_action :require_signature!, only: :show, if: -> { request.format == :json && authorized_fetch_mode? }
  before_action :set_status
  before_action :set_instance_presenter
  before_action :set_link_headers
  before_action :redirect_to_original, only: :show
  before_action :set_referrer_policy_header, only: :show
  before_action :set_cache_headers
  before_action :set_body_classes
  before_action :set_autoplay, only: :embed

  content_security_policy only: :embed do |p|
    p.frame_ancestors(false)
  end

  def show
    respond_to do |format|
      format.html do
        expires_in 10.seconds, public: true if current_account.nil?
        set_ancestors
        set_descendants
      end

      format.json do
        expires_in 3.minutes, public: @status.distributable? && public_fetch_mode?
        render json: @status, content_type: 'application/activity+json', serializer: ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter
      end
    end
  end

  def activity
    expires_in 3.minutes, public: @status.distributable? && public_fetch_mode?
    render json: @status, content_type: 'application/activity+json', serializer: ActivityPub::ActivitySerializer, adapter: ActivityPub::Adapter
  end

  def embed
    raise ActiveRecord::RecordNotFound if @status.hidden?

    expires_in 180, public: true
    response.headers['X-Frame-Options'] = 'ALLOWALL'

    render layout: 'embedded'
  end

  private

  def set_body_classes
    @body_classes = 'with-modals'
  end

  def set_link_headers
    response.headers['Link'] = LinkHeader.new([[ActivityPub::TagManager.instance.uri_for(@status), [%w(rel alternate), %w(type application/activity+json)]]])
  end

  def set_status
    @status = @account.statuses.find(params[:id])
    authorize @status, :show?
  rescue Mastodon::NotPermittedError
    raise ActiveRecord::RecordNotFound
  end

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end

  def redirect_to_original
    redirect_to ActivityPub::TagManager.instance.url_for(@status.reblog) if @status.reblog?
  end

  def set_referrer_policy_header
    response.headers['Referrer-Policy'] = 'origin' unless @status.distributable?
  end

  def set_autoplay
    @autoplay = truthy_param?(:autoplay)
  end
end
