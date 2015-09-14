_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'

class ConfigurationGenerator
  constructor: ->
    @configure = sinon.stub()

class ConfigurationSaver
  constructor: ->
    @save = sinon.stub()

class MeshbluHttp
  constructor: ->
    @whoami = sinon.stub()
    @updateDangerously = sinon.stub()

describe 'FlowDeployer', ->
  describe 'when constructed with a flow', ->
    beforeEach ->
      @flowUuid = 5
      @flowToken = 13
      @forwardUrl = "http://www.zombo.com"
      @configuration = erik_is_happy: true

      @sut = new FlowDeployer @flowUuid, @flowToken, @forwardUrl, { ConfigurationGenerator: ConfigurationGenerator, ConfigurationSaver: ConfigurationSaver, MeshbluHttp: MeshbluHttp }

      @sut.configurer.configure.yields null, _.cloneDeep(@configuration)
      @sut.saver.save.yields null, true
      @sut.meshbluHttp.whoami.yields null, uuid: 1, flow: {a: 1, b: 5}


    describe 'when deploy is called', ->
      beforeEach (done)->
        @sut.deploy  => done()

      it 'should call configuration generator with the flow', ->
        expect(@sut.configurer.configure).to.have.been.calledWith {a: 1, b: 5}

      it 'should call configuration saver with the flow', ->
        expect(@sut.saver.save).to.have.been.calledWith @configuration

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
        @sut.configurer.configure.yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        @sut.configurer.configure.yields null, { erik_likes_me: true}
        @sut.saver.save.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        @sut.configurer.configure.yields null, { erik_likes_me: 'more than you know'}
        @sut.saver.save.yields null, {finally_i_am_happy: true}

        @sut.deploy  (@error, @result) => done()

      it 'should not yield an error', ->
        expect(@error).to.not.exist


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
      it 'should exist', ->
        expect(@sut.startFlow).to.exist

    describe 'stopFlow', ->
      it 'should exist', ->
        expect(@sut.stopFlow).to.exist
