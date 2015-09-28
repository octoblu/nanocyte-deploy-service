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
      @flowUuid = 'the-flow-uuid'
      @flowToken = 'the-flow-token'
      @forwardUrl = "http://www.zombo.com"
      @configuration = erik_is_happy: true

      options =
        flowUuid: @flowUuid
        flowToken: @flowToken
        forwardUrl: @forwardUrl
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

      @request.get.yields null, {}, {a: 1, b: 5}

    describe 'when deploy is called', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null
        @configurationSaver.clear.yields null
        @configurationSaver.save.yields null
        @sut.setupDeviceForwarding = sinon.stub().yields null
        @sut.deploy  => done()

      it 'should call configuration generator with the flow', ->
        expect(@configurationGenerator.configure).to.have.been.calledWith { a: 1, b: 5 }, 'the-flow-token'

      it 'should call configuration saver with the flow', ->
        expect(@configurationSaver.save).to.have.been.called

      it 'should call request.get', ->
        options =
          json: true
          auth :
            user: 'some-user-uuid'
            pass: 'some-user-token'

        expect(@request.get).to.have.been.calledWith "https://api.octoblu.com/api/flows/#{@flowUuid}", options

    describe 'when deploy is called and flow get errored', ->
      beforeEach (done)->
        @request.get.yields new Error 'whoa shits bad', null
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
              url: @forwardUrl
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
        @sut.setupDeviceForwarding @device, (@error, @result) => done()

      it "should update a meshblu device with the webhook to wherever it's going", ->
        expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith @flowUuid, @pullMessageHooks
        expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith @flowUuid, @updateMessageHooks

    describe 'startFlow', ->
      describe 'when called and there is no errors', ->
        beforeEach (done) ->
          @sut.meshbluHttp.message.yields null, null
          @sut.startFlow (@error, @result) => done()

        it 'should message meshblu with the a flow start message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: [@flowUuid]
            payload:
              from: "engine-start"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "engine-start"

          @sut.meshbluHttp.message.yields new Error 'duck army', null
          @sut.startFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist

    describe 'stopFlow', ->
      describe 'when called and there is no error', ->
        beforeEach (done) ->
          @sut.meshbluHttp.message.yields null, null
          @sut.stopFlow (@error, @result) => done()

        it 'should message meshblu with the a flow stop message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: [@flowUuid]
            payload:
              from: "engine-stop"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @sut.meshbluHttp.message.yields new Error 'look at meeeeee', null
          @sut.stopFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist
