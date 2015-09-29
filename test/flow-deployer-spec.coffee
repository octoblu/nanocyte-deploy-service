_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'

class MeshbluHttp
  constructor: ->
    @updateDangerously = sinon.stub()
    @message = sinon.stub()

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

      @configurationGenerator = configure: sinon.stub()
      @configurationSaver =
        save: sinon.stub()
        clear: sinon.stub()

      @sut = new FlowDeployer options,
        configurationGenerator: @configurationGenerator
        configurationSaver: @configurationSaver
        MeshbluHttp: MeshbluHttp
        request: @request

      @request.get.withArgs('https://api.octoblu.com/api/flows/the-flow-uuid').yields null, {}, {a: 1, b: 5}
      @request.get.withArgs('https://api.octoblu.com/api/user').yields null, {}, {api: {}}

    describe 'when deploy is called', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null
        @configurationSaver.clear.yields null
        @configurationSaver.save.yields null
        @sut.setupDeviceForwarding = sinon.stub().yields null
        @sut.deploy  => done()

      it 'should call configuration generator with the flow', ->
        expect(@configurationGenerator.configure).to.have.been.calledWith
          flowData: { a: 1, b: 5 }
          userData: {api: {}}
          flowToken: 'the-flow-token'

      it 'should call configuration saver with the flow', ->
        expect(@configurationSaver.save).to.have.been.called

      it 'should call request.get', ->
        options =
          json: true
          auth :
            user: 'some-user-uuid'
            pass: 'some-user-token'

        expect(@request.get).to.have.been.calledWith 'https://api.octoblu.com/api/flows/the-flow-uuid', options
        expect(@request.get).to.have.been.calledWith 'https://api.octoblu.com/api/user', options

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

    describe 'when deploy is called and the configuration generator returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration clear returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null, { erik_likes_me: true}
        @configurationSaver.clear.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

      it 'should not call save', ->
        expect(@configurationSaver.save).to.not.have.been.called

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null, { erik_likes_me: true}
        @configurationSaver.clear.yields null
        @configurationSaver.save.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        @configurationGenerator.configure.yields null, { erik_likes_me: 'more than you know'}
        @configurationSaver.clear.yields null
        @configurationSaver.save.yields null, {finally_i_am_happy: true}
        @sut.setupDeviceForwarding = sinon.stub().yields null

        @sut.deploy  (@error, @result) => done()

      it 'should call setupDeviceForwarding', ->
        expect(@sut.setupDeviceForwarding).to.have.been.called

    describe 'setupDeviceForwarding', ->
      beforeEach (done) ->
        @updateMessageHooks =
          $addToSet:
            'meshblu.messageHooks':
              generateAndForwardMeshbluCredentials: true
              url: 'http://www.zombo.com'
              method: 'POST'
              name: 'nanocyte-flow-deploy'

        @pullMessageHooks =
          $pull:
            'meshblu.messageHooks':
              name: 'nanocyte-flow-deploy'

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

        @sut.meshbluHttp.updateDangerously.yields null, null
        @sut.setupDeviceForwarding (@error, @result) => done()

      it "should update a meshblu device with the webhook to wherever it's going", ->
        expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @pullMessageHooks
        expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith 'the-flow-uuid', @updateMessageHooks

    describe 'startFlow', ->
      describe 'when called and there is no errors', ->
        beforeEach (done) ->
          @sut.meshbluHttp.updateDangerously.yields null
          @sut.meshbluHttp.message.yields null, null
          @sut.startFlow (@error, @result) => done()

        it 'should update meshblu device status', ->
          expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith
            $set:
              online: true

        it 'should message meshblu with the a flow start message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: ['the-flow-uuid']
            payload:
              from: "engine-start"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "engine-start"

          @sut.meshbluHttp.updateDangerously.yields null
          @sut.meshbluHttp.message.yields new Error 'duck army', null
          @sut.startFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist

    describe 'stopFlow', ->
      describe 'when called and there is no error', ->
        beforeEach (done) ->
          @sut.meshbluHttp.updateDangerously.yields null
          @sut.meshbluHttp.message.yields null, null
          @sut.stopFlow (@error, @result) => done()

        it 'should update the meshblu device with as offline', ->
          expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith
            $set:
              online: false

        it 'should message meshblu with the a flow stop message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: ['the-flow-uuid']
            payload:
              from: "engine-stop"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @sut.meshbluHttp.updateDangerously.yields null
          @sut.meshbluHttp.message.yields new Error 'look at meeeeee', null
          @sut.stopFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist
