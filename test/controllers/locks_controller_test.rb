# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe LocksController do
  def create_lock(resource = nil, options = {})
    format = options.delete(:format) || :html
    params = {resource_id: resource&.id.to_s, resource_type: resource&.class&.name.to_s, description: 'DESC'}
    params.merge!(options)
    post :create, params: {lock: params}, format: format
  end

  let(:stage) { stages(:test_staging) }
  let(:prod_stage) { stages(:test_production) }
  let(:environment) { environments(:production) }
  let(:lock) { stage.create_lock! user: users(:deployer) }
  let(:global_lock) { Lock.create! user: users(:deployer) }

  before { request.headers['HTTP_REFERER'] = '/back' }

  describe "#for_stage_lock?" do
    it "raises on unsupported action" do
      @controller.stubs(action_name: 'show')
      assert_raises RuntimeError do
        @controller.send(:for_stage_lock?)
      end
    end
  end

  describe "#require_stage" do
    it "raises on unsupported action" do
      @controller.stubs(action_name: 'show')
      assert_raises RuntimeError do
        @controller.send(:require_stage)
      end
    end
  end

  as_a_viewer do
    unauthorized :post, :create

    it 'is unauthorized when doing a post to create a stage lock' do
      create_lock stage
      assert_response :unauthorized
    end

    it 'is unauthorized when doing a delete to destroy a stage lock' do
      delete :destroy, params: {id: lock.id}
      assert_response :unauthorized
    end

    it 'is unauthorized when doing a delete to destroy a global lock' do
      delete :destroy, params: {id: global_lock.id}
      assert_response :unauthorized
    end

    describe '#index' do
      it "renders" do
        Lock.create!(user: users(:admin))

        get :index, format: :json

        assert_response :success
        data = JSON.parse(response.body)
        data.keys.must_equal ['locks']
        data['locks'].first.keys.must_include 'description'
      end
    end
  end

  as_a_project_deployer do
    unauthorized :post, :create
    unauthorized :delete, :destroy_via_resource

    it 'is not authorized to create a global lock' do
      create_lock
      assert_response :unauthorized
    end

    it 'is not authorized to create an environment lock' do
      create_lock environment
      assert_response :unauthorized
    end

    describe '#create' do
      before { travel_to Time.now }
      after { travel_back }

      it 'creates a stage lock' do
        create_lock stage, delete_in: 3600
        assert_redirected_to '/back'
        assert flash[:notice]

        stage.reload

        lock = stage.lock
        lock.warning?.must_equal(false)
        lock.description.must_equal 'DESC'
        lock.delete_at.must_equal(Time.now + 3600)
      end

      it 'redirects and shows error if stage lock is invalid' do
        create_lock(stage, delete_at: 1.hour.ago)
        assert_redirected_to '/back'
        assert flash[:error]
      end

      it 'creates a stage warning' do
        create_lock stage, warning: true
        assert_redirected_to '/back'
        assert flash[:notice]

        stage.reload

        lock = stage.lock
        lock.warning?.must_equal(true)
        lock.description.must_equal 'DESC'
      end

      it 'creates a via json' do
        create_lock stage, format: :json
        assert_response :success
        JSON.parse(response.body).fetch("lock").fetch("id").must_equal Lock.last.id
      end

      describe 'with PRODUCTION_STAGE_LOCK_REQUIRES_ADMIN' do
        with_env 'PRODUCTION_STAGE_LOCK_REQUIRES_ADMIN' => 'true'

        it 'cannot create a stage lock for a production stage' do
          create_lock prod_stage

          assert_response :unauthorized
        end

        it 'creates a stage lock' do
          create_lock stage, delete_in: 3600
          assert_redirected_to '/back'
          assert flash[:notice]

          stage.reload

          lock = stage.lock
          lock.warning?.must_equal(false)
          lock.description.must_equal 'DESC'
          lock.delete_at.must_equal(Time.now + 3600)
        end
      end
    end

    describe '#destroy' do
      let(:lock) { stage.create_lock!(user: users(:deployer)) }

      it 'destroys a stage lock' do
        delete :destroy, params: {id: lock.id}

        assert_redirected_to '/back'
        assert flash[:notice]

        Lock.count.must_equal 0
      end

      it 'destroys an invalid lock' do
        lock.update_column(:description, '')
        delete :destroy, params: {id: lock.id}
        assert_redirected_to '/back'
        Lock.count.must_equal 0
      end

      it 'destroys via json' do
        delete :destroy, params: {id: lock.id}, format: :json
        assert_response :success
        Lock.count.must_equal 0
      end
    end

    describe '#destroy with PRODUCTION_STAGE_LOCK_REQUIRES_ADMIN' do
      with_env 'PRODUCTION_STAGE_LOCK_REQUIRES_ADMIN' => 'true'

      it 'no change in default behavior for non-production stage lock' do
        delete :destroy, params: {id: lock.id}

        assert_redirected_to '/back'
        assert flash[:notice]

        Lock.count.must_equal 0
      end

      it 'cannot destroy a stage production lock' do
        stage.update_column(:production, true)
        delete :destroy, params: {id: lock.id}

        assert_response :unauthorized
      end
    end
  end

  as_an_admin do
    describe '#create' do
      it 'creates a global lock' do
        create_lock
        assert_redirected_to '/back'
        assert flash[:notice]

        lock = Lock.global.first
        lock.description.must_equal 'DESC'
      end

      it 'creates an environment lock' do
        create_lock environment
        assert_redirected_to '/back'
        assert flash[:notice]

        lock = environment.lock
        lock.description.must_equal 'DESC'
      end
    end

    describe '#destroy' do
      it 'destroys a global lock' do
        delete :destroy, params: {id: global_lock.id}

        assert_redirected_to '/back'
        assert flash[:notice]

        Lock.count.must_equal 0
      end
    end

    describe "#destroy_via_resource" do
      before { Lock.create!(user: users(:admin)) }

      it "unlocks global" do
        assert_difference "Lock.count", -1 do
          delete :destroy_via_resource,
            params: {resource_id: nil, resource_type: nil},
            format: :json
        end
        assert_response :success
      end

      it "unlocks resource" do
        stage = stages(:test_staging)
        Lock.create!(user: users(:admin), resource: stage)
        assert_difference "Lock.count", -1 do
          delete :destroy_via_resource,
            params: {resource_id: stage.id, resource_type: 'Stage'},
            format: :json
        end
        assert_response :success
      end

      it "fails with unfound lock" do
        assert_raises ActiveRecord::RecordNotFound do
          delete :destroy_via_resource,
            params: {resource_id: 333223, resource_type: 'Stage'},
            format: :json
        end
      end

      it "fails without parameters" do
        delete :destroy_via_resource, format: :json
        assert_response :bad_request
        JSON.parse(response.body).must_equal "status" => 400, "error" => {"resource_id" => ["is required"]}
      end
    end
  end
end
