# Guard API with OAuth 2.0 Access Token

require 'rack/oauth2'

module APIGuard
  extend ActiveSupport::Concern

  included do |base|
    # OAuth2 Resource Server Authentication
    use Rack::OAuth2::Server::Resource::Bearer, 'The API' do |request|
      # The authenticator only fetches the raw token string

      # Must yield access token to store it in the env
      request.access_token
    end

    helpers HelperMethods

    install_error_responders(base)
  end

  # Helper Methods for Grape Endpoint
  module HelperMethods
    # Invokes the doorkeeper guard.
    #
    # If token string is blank, then it raises MissingTokenError.
    #
    # If token is presented and valid, then it sets @current_user.
    #
    # If the token does not have sufficient scopes to cover the requred scopes,
    # then it raises InsufficientScopeError.
    #
    # If the token is expired, then it raises ExpiredError.
    #
    # If the token is revoked, then it raises RevokedError.
    #
    # If the token is not found (nil), then it raises TokenNotFoundError.
    #
    # Arguments:
    #
    #   scopes: (optional) scopes required for this guard.
    #           Defaults to empty array.
    #
    def guard!(scopes: [])
      token_string = get_token_string()

      if token_string.blank?
        raise MissingTokenError

      elsif (access_token = find_access_token(token_string)).nil?
        raise TokenNotFoundError

      else
        case validate_access_token(access_token, scopes)
        when AccessTokenValidation::INSUFFICIENT_SCOPE
          raise InsufficientScopeError.new(scopes)

        when AccessTokenValidation::EXPIRED
          raise ExpiredError

        when AccessTokenValidation::REVOKED
          raise RevokedError

        when AccessTokenValidation::VALID
          @current_application = access_token.application_id
          resource_owner_id = access_token.resource_owner_id
          @current_user = User.find(resource_owner_id) if resource_owner_id
        end
      end
    end

    def current_application
      @current_application
    end

    def current_user
      @current_user
    end

    private
    def get_token_string
      # The token was stored after the authenticator was invoked.
      # It could be nil. The authenticator does not check its existence.
      request.env[Rack::OAuth2::Server::Resource::ACCESS_TOKEN]
    end

    def find_access_token(token)
      # Doorkeeper::OAuth::Token.authenticate(request, *Doorkeeper.configuration.access_token_methods)
      access_token = Doorkeeper::AccessToken.by_token(token)
      access_token.revoke_previous_refresh_token! if access_token
      access_token
    end

    def validate_access_token(access_token, scopes)
      AccessTokenValidation.validate(access_token, scopes: scopes)
    end
  end

  module ClassMethods
    # Installs the doorkeeper guard on the whole Grape API endpoint.
    #
    # Arguments:
    #
    #   scopes: (optional) scopes required for this guard.
    #           Defaults to empty array.
    #
    def guard_all!(scopes: [])
      before do
        guard! scopes: scopes
      end
    end

    private
    def install_error_responders(base)
      error_classes = [ MissingTokenError, TokenNotFoundError,
                        ExpiredError, RevokedError, InsufficientScopeError]

      base.send :rescue_from, *error_classes, oauth2_bearer_token_error_handler
    end

    def oauth2_bearer_token_error_handler
      Proc.new {|e|
        response = case e
          when MissingTokenError
            Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new

          when TokenNotFoundError
            Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new(
              :invalid_token,
              "Bad Access Token.")

          when ExpiredError
            Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new(
              :invalid_token,
              "Token is expired. You can either do re-authorization or token refresh.")

          when RevokedError
            Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new(
              :invalid_token,
              "Token was revoked. You have to re-authorize from the user.")

          when InsufficientScopeError
            # FIXME: ForbiddenError (inherited from Bearer::Forbidden of Rack::Oauth2)
            # does not include WWW-Authenticate header, which breaks the standard.
            Rack::OAuth2::Server::Resource::Bearer::Forbidden.new(
              :insufficient_scope,
              Rack::OAuth2::Server::Resource::ErrorMethods::DEFAULT_DESCRIPTION[:insufficient_scope],
              { :scope => e.scopes})
          end

        response.finish
      }
    end
  end

  #
  # Exceptions
  #

  class MissingTokenError < StandardError; end

  class TokenNotFoundError < StandardError; end

  class ExpiredError < StandardError; end

  class RevokedError < StandardError; end

  class InsufficientScopeError < StandardError
    attr_reader :scopes
    def initialize(scopes)
      @scopes = scopes
    end
  end
end
