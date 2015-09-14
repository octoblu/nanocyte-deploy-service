_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'

class ConfigurationGenerator  
  configure : sinon.stub().yields null

class ConfigurationSaver
  save: sinon.stub().yields null

class MeshbluHttp
  constructor: ->
    @whoami = sinon.stub()
    @updateDangerously = sinon.stub()
    @message = sinon.stub()

describe 'FlowDeployer', ->
  describe.only 'when constructed with a flow', ->
    beforeEach ->
      @flowUuid = 5
      @flowToken = 13
      @forwardUrl = "http://www.zombo.com"
      @configuration = erik_is_happy: true

      @sut = new FlowDeployer @flowUuid, @flowToken, @forwardUrl, { ConfigurationGenerator: ConfigurationGenerator, ConfigurationSaver: ConfigurationSaver, MeshbluHttp: MeshbluHttp }
      ConfigurationGenerator.prototype.configure = sinon.stub().yields null, _.cloneDeep(@configuration)
      ConfigurationSaver.prototype.save = sinon.stub().yields null, true
      @sut.meshbluHttp.whoami.yields null, uuid: 1, flow: {a: 1, b: 5}


    describe 'when deploy is called', ->
      beforeEach (done)->
        @sut.setupDeviceForwarding = sinon.stub().yields null
        @sut.deploy  => done()

      it 'should call configuration generator with the flow', ->
        expect(ConfigurationGenerator.prototype.configure).to.have.been.called

      it 'should call configuration saver with the flow', ->
        expect(ConfigurationSaver.prototype.save).to.have.been.called

    describe 'when deploy is called and whoami errored', ->
      beforeEach (done)->
        @sut.meshbluHttp.whoami.yields new Error 'whoa shits bad', null
        @sut.deploy  (@error, @result) => done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration generator returns an error', ->
      beforeEach (done)->
        ConfigurationGenerator.prototype.configure = sinon.stub().yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        ConfigurationGenerator.prototype.configure = sinon.stub().yields null, { erik_likes_me: true}
        ConfigurationSaver.prototype.save = sinon.stub().yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        ConfigurationGenerator.prototype.configure = sinon.stub().yields null, { erik_likes_me: 'more than you know'}
        ConfigurationSaver.prototype.save = sinon.stub().yields null, {finally_i_am_happy: true}
        @sut.setupDeviceForwarding = sinon.stub().yields null

        @sut.deploy  (@error, @result) => done()

      it 'should call setupDeviceForwarding', ->
        expect(@sut.setupDeviceForwarding).to.have.been.called

    describe 'setupDeviceForwarding', ->
      describe 'when called with a flow that does not have messageHooks', ->
        beforeEach (done) ->
          @createMessageHooks =
            $set:
              'meshblu.messageHooks': [{ url: @forwardUrl, method: 'POST' }]
          @device = uuid: 1, flow: {a: 1, b: 5}
          @sut.meshbluHttp.updateDangerously.yields null, null
          @sut.setupDeviceForwarding @device, (@error, @result) => done()

        it "should update a meshblu device with the webhook to wherever it's going", ->
          expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith @flowUuid, @createMessageHooks

      describe 'when called with a flow that has messageHooks', ->
        beforeEach (done) ->
          @updateMessageHooks =
            $push:
              'meshblu.messageHooks': { url: @forwardUrl, method: 'POST' }

          @device =
            uuid: 1,
            flow: {a: 1, b: 5},
            meshblu:
              messageHooks: [ {url: 'http://www.neopets.com', method: 'DELETE'} ]

          @sut.meshbluHttp.updateDangerously.yields null, null
          @sut.setupDeviceForwarding @device, (@error, @result) => done()

        it "should update a meshblu device with the webhook to wherever it's going", ->
          expect(@sut.meshbluHttp.updateDangerously).to.have.been.calledWith @flowUuid, @updateMessageHooks

      describe 'when called with a flow that has the same messageHook already', ->
        beforeEach (done) ->
          @device =
            uuid: 1,
            flow: {a: 1, b: 5},
            meshblu:
              messageHooks: [
                {url: 'http://www.neopets.com', method: 'DELETE'}
                {url: @forwardUrl, method: 'POST'}
              ]

          @sut.setupDeviceForwarding @device, (@error, @result) => done()

        it "should not update a meshblu device", ->
          expect(@sut.meshbluHttp.updateDangerously).to.not.have.been.called

    describe 'startFlow', ->
      describe 'when called and there is no errors', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "meshblu-start"

          @sut.meshbluHttp.message.yields null, null
          @sut.startFlow (@error, @result) => done()

        it 'should message meshblu with the a flow start message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith [@flowUuid], @message

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "meshblu-start"

          @sut.meshbluHttp.message.yields new Error 'duck army', null
          @sut.startFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist

    describe 'stopFlow', ->
      describe 'when called and there is no error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "meshblu-stop"

          @sut.meshbluHttp.message.yields null, null
          @sut.stopFlow (@error, @result) => done()

        it 'should message meshblu with the a flow stop message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith [@flowUuid], @message

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @message =
            payload:
              from: "meshblu-stop"

          @sut.meshbluHttp.message.yields new Error 'look at meeeeee', null
          @sut.stopFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist
