_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'


describe 'FlowDeployer', ->
  describe 'when constructed with a flow', ->
    beforeEach ->
      @request = get: sinon.stub()
      @configuration = erik_is_happy: true

      options =
        flowUuid: 'the-flow-uuid'
        flowToken: 'the-flow-token'
        forwardUrl: 'http://www.zombo.com'
        instanceId: 'an-instance-id'
        userUuid: 'some-user-uuid'
        userToken: 'some-user-token'
        octobluUrl: 'https://api.octoblu.com'
        deploymentUuid: 'the-deployment-uuid'
        flowLoggerUuid: 'flow-logger-uuid'

      @configurationGenerator =
        configure: sinon.stub()

      @configurationSaver =
        save: sinon.stub()
        stop: sinon.stub()

      @meshbluHttp =
        message:            sinon.stub()
        updateDangerously:  sinon.stub()
        createSubscription: sinon.stub()
        whoami:             sinon.stub()

      MeshbluHttp = sinon.spy => @meshbluHttp

      @sut = new FlowDeployer options,
        configurationGenerator: @configurationGenerator
        configurationSaver: @configurationSaver
        MeshbluHttp: MeshbluHttp
        request: @request

      @request.get.withArgs('https://api.octoblu.com/api/flows/the-flow-uuid').yields null, {}, {a: 1, b: 5}
      @request.get.withArgs('https://api.octoblu.com/api/user').yields null, {}, {api: {}}

    describe 'when deploy is called', ->
      beforeEach (done)->
        flowConfig =
          'some': 'thing'
          'subscribe-devices':
            config:
              'broadcast.sent': ['subscribe-to-this-uuid']

        @configurationGenerator.configure.yields null, flowConfig, {stop: 'config'}
        @configurationSaver.stop.yields null
        @configurationSaver.save.yields null
        @sut.setupDevice = sinon.stub().yields null
        @sut.deploy  => done()

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.called
        firstArg = @meshbluHttp.message.firstCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'begin'
            message:  undefined

      it 'should call configuration generator with the flow', ->
        expect(@configurationGenerator.configure).to.have.been.calledWith
          flowData: { a: 1, b: 5 }
          userData: {api: {}}
          deploymentUuid: 'the-deployment-uuid'
          flowToken: 'the-flow-token'

      it 'should call configuration saver with the flow', ->
        expect(@configurationSaver.save).to.have.been.calledWith(
          flowId: 'the-flow-uuid'
          instanceId: 'an-instance-id'
          flowData:
            'some': 'thing'
            'subscribe-devices':
              config:
                'broadcast.sent': ['subscribe-to-this-uuid']
        )
        expect(@configurationSaver.save).to.have.been.calledWith(
          flowId: 'the-flow-uuid-stop'
          instanceId: 'an-instance-id'
          flowData:
            stop: 'config'
        )

      it 'should call request.get', ->
        options =
          json: true
          auth :
            user: 'some-user-uuid'
            pass: 'some-user-token'

        expect(@request.get).to.have.been.calledWith 'https://api.octoblu.com/api/flows/the-flow-uuid', options
        expect(@request.get).to.have.been.calledWith 'https://api.octoblu.com/api/user', options

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.called
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'end'
            message:  undefined

    describe 'when deploy is called and user GET errored', ->
      beforeEach (done) ->
        userUrl = 'https://api.octoblu.com/api/user'
        @request.get.withArgs(userUrl).yields new Error 'whoa, thats not a user', null
        @sut.deploy  (@error, @result) => done()

      it 'should call request.get', ->
        expect(@request.get).to.have.been.called

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.calledTwice
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'error'
            message:  'whoa, thats not a user'

    describe 'when deploy is called and flow get errored', ->
      beforeEach (done) ->
        userUrl = 'https://api.octoblu.com/api/user'
        @request.get.withArgs(userUrl).yields null

        flowUrl = 'https://api.octoblu.com/api/flows/the-flow-uuid'
        @request.get.withArgs(flowUrl).yields new Error 'whoa, shoots bad', null
        @sut.deploy  (@error, @result) => done()

      it 'should call request.get', ->
        expect(@request.get).to.have.been.called

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.calledTwice
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'error'
            message:  'whoa, shoots bad'

    describe 'when deploy is called and the configuration generator returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.calledTwice
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'error'
            message:  'Oh noes'

    describe 'when deploy is called and the configuration stop returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null, { erik_likes_me: true}
        @configurationSaver.stop.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should not call save', ->
        expect(@configurationSaver.save).to.not.have.been.called

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.calledTwice
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'error'
            message:  'Erik can never like me enough'

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null, { erik_likes_me: true}
        @configurationSaver.stop.yields null
        @configurationSaver.save.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should message the FLOW_LOGGER_UUID', ->
        expect(@meshbluHttp.message).to.have.been.calledTwice
        firstArg = @meshbluHttp.message.secondCall.args[0]
        delete firstArg.payload.date

        expect(firstArg).to.deep.equal
          devices: ['flow-logger-uuid']
          payload:
            application: 'flow-deploy-service'
            deploymentUuid: 'the-deployment-uuid'
            flowUuid: 'the-flow-uuid'
            userUuid: 'some-user-uuid'
            workflow: 'flow-start'
            state:    'error'
            message:  'Erik can never like me enough'

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        @configurationGenerator.configure.yields null, { erik_likes_me: 'more than you know'}
        @configurationSaver.stop.yields null
        @configurationSaver.save.yields null, {finally_i_am_happy: true}
        @sut.setupDevice = sinon.stub().yields null

        @sut.deploy  (@error, @result) => done()

      it 'should call setupDeviceForwarding', ->
        expect(@sut.setupDevice).to.have.been.called


    describe 'createSubscriptions', ->
      beforeEach (done) ->
        @meshbluHttp.createSubscription.yields null
        flowConfig =
          'subscribe-devices':
            config:
              'broadcast.sent': ['subscribe-to-this-uuid']
        @sut.createSubscriptions flowConfig, done

      it "should create the subscription to the device's", ->
        subscriberUuid = 'the-flow-uuid'
        emitterUuid = 'subscribe-to-this-uuid'
        type = 'broadcast.sent'
        expect(@meshbluHttp.createSubscription).to.have.been.calledWith {subscriberUuid, emitterUuid, type}

    describe 'setupDeviceForwarding', ->
      beforeEach (done) ->
        @updateMessageHooks =
          $addToSet:
            'meshblu.forwarders.broadcast.received':
              signRequest: true
              url: 'http://www.zombo.com'
              method: 'POST'
              name: 'nanocyte-flow-deploy'
              type: 'webhook'
            'meshblu.forwarders.message.received':
              signRequest: true
              url: 'http://www.zombo.com'
              method: 'POST'
              name: 'nanocyte-flow-deploy'
              type: 'webhook'

        @pullMessageHooks =
          $pull:
            'meshblu.forwarders.received':
              name: 'nanocyte-flow-deploy'
            'meshblu.messageHooks':
              name: 'nanocyte-flow-deploy'
            'meshblu.forwarders.broadcast.received':
              name: 'nanocyte-flow-deploy'
            'meshblu.forwarders.message.received':
              name: 'nanocyte-flow-deploy'

        @removeOldMessageHooks =
          $unset:
            'meshblu.forwarders.broadcast': ''

        @device =
          uuid: 1
          flow: {a: 1, b: 5}
          meshblu:
            messageHooks: [
              generateAndForwardMeshbluCredentials: true
              url: 'http://www.neopets.com'
              method: 'DELETE'
              name: 'nanocyte-flow-deploy'
            ]

        @meshbluHttp.whoami.yields null, meshblu: forwarders: broadcast: []
        @meshbluHttp.updateDangerously.yields null, null
        @sut.setupDeviceForwarding (@error, @result) => done()

      it "should update a meshblu device with the webhook to wherever it's going", ->
        expect(@meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @removeOldMessageHooks
        expect(@meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @pullMessageHooks
        expect(@meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @updateMessageHooks

    describe 'setupMessageSchema', ->
      beforeEach (done) ->
        @updateDevice = $set:
          messageSchema:
            type: 'object'
            properties:
              from:
                type: 'string'
                title: 'Trigger'
                required: true
                enum: [ 'a', 'c' ]
              data:
                type: 'string'

          messageFormSchema: [
            {
              key: 'from'
              titleMap:
                'a' : 'multiply (a)'
                'c' : 'rabbits (c)' 
            }
            'data'
          ]

        nodes = [
          {
            class: 'trigger'
            id: 'a'
            name: 'multiply'
          },
          {
            class: 'not-a-trigger'
            id: 'b'
            name: 'like'
          },
          {
            class: 'trigger'
            id: 'c'
            name: 'rabbits'
          }
        ]

        @sut.meshbluHttp.updateDangerously.yields null, null
        @sut.setupMessageSchema nodes, (@error, @result) => done()

      it "should update a meshblu device with message schema for triggers", ->
        expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @updateDevice

    describe 'startFlow', ->
      describe 'when called and there is no errors', ->
        beforeEach (done) ->
          @meshbluHttp.updateDangerously.yields null
          @meshbluHttp.message.yields null, null
          @sut.startFlow (@error, @result) => done()

        it 'should update meshblu device status', ->
          expect(@meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid',
            $set:
              online: true
              deploying: false
              stopping: false

        it 'should message meshblu with the a flow start message', ->
          expect(@meshbluHttp.message).to.have.been.calledWith
            devices: ['the-flow-uuid']
            payload:
              from: "engine-start"

        it 'should message meshblu with a subscribe:pulse message', ->
          expect(@meshbluHttp.message).to.have.been.calledWith
            devices: ['the-flow-uuid']
            topic: 'subscribe:pulse'

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "engine-start"

          @meshbluHttp.updateDangerously.yields null
          @meshbluHttp.message.yields new Error 'duck army', null
          @sut.startFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist

    describe 'stopFlow', ->
      describe 'when called and there is no error', ->
        beforeEach (done) ->
          @meshbluHttp.updateDangerously.yields null
          @meshbluHttp.message.yields null, null
          @sut.stopFlow (@error, @result) => done()

        it 'should update the meshblu device with as offline', ->
          expect(@meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid',
            $set:
              online: false
              deploying: false
              stopping: false

        it 'should message meshblu with the a flow stop message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: ['the-flow-uuid']
            payload:
              from: "engine-stop"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @meshbluHttp.updateDangerously.yields null
          @meshbluHttp.message.yields new Error 'look at meeeeee', null
          @sut.stopFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist
