_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'

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

      options =
        flowUuid: @flowUuid
        flowToken: @flowToken
        forwardUrl: @forwardUrl
        instanceId: 'an-instance-id'

      @configurationGenerator = configure: sinon.stub()
      @configurationSaver = save: sinon.stub()

      @sut = new FlowDeployer options,
        configurationGenerator: @configurationGenerator
        configurationSaver: @configurationSaver
        MeshbluHttp: MeshbluHttp

      @sut.meshbluHttp.whoami.yields null, uuid: 1, flow: {a: 1, b: 5}

    describe 'when deploy is called', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null
        @configurationSaver.save.yields null
        @sut.setupDeviceForwarding = sinon.stub().yields null
        @sut.deploy  => done()

      it 'should call configuration generator with the flow', ->
        expect(@configurationGenerator.configure).to.have.been.called

      it 'should call configuration saver with the flow', ->
        expect(@configurationSaver.save).to.have.been.called

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
        @configurationGenerator.configure.yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        @configurationGenerator.configure.yields null, { erik_likes_me: true}
        @configurationSaver.save.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        @configurationGenerator.configure.yields null, { erik_likes_me: 'more than you know'}
        @configurationSaver.save.yields null, {finally_i_am_happy: true}
        @sut.setupDeviceForwarding = sinon.stub().yields null

        @sut.deploy  (@error, @result) => done()

      it 'should call setupDeviceForwarding', ->
        expect(@sut.setupDeviceForwarding).to.have.been.called

    describe 'setupDeviceForwarding', ->
      beforeEach (done) ->
        @updateMessageHooks =
          $addToSet:
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

    describe 'startFlow', ->
      describe 'when called and there is no errors', ->
        beforeEach (done) ->
          @sut.meshbluHttp.message.yields null, null
          @sut.startFlow (@error, @result) => done()

        it 'should message meshblu with the a flow start message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: [@flowUuid]
            payload:
              from: "meshblu-start"

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
          @sut.meshbluHttp.message.yields null, null
          @sut.stopFlow (@error, @result) => done()

        it 'should message meshblu with the a flow stop message', ->
          expect(@sut.meshbluHttp.message).to.have.been.calledWith
            devices: [@flowUuid]
            payload:
              from: "meshblu-stop"

      describe 'when called and meshblu returns an error', ->
        beforeEach (done) ->
          @sut.meshbluHttp.message.yields new Error 'look at meeeeee', null
          @sut.stopFlow (@error, @result) => done()

        it 'should call the callback with the error', ->
          expect(@error).to.exist
