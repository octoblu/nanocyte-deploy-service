_ = require 'lodash'
FlowDeployer = require '../src/flow-deployer'

class ConfigurationGenerator
  configure: sinon.stub()

class ConfigurationSaver
  save: sinon.stub()

describe 'FlowDeployer', ->
  describe 'when constructed with a flow', ->
    beforeEach ->
      @flow = {}
      @configuration = { erik_is_happy: true}
      ConfigurationGenerator.prototype.configure.yields null, _.cloneDeep(@configuration)
      ConfigurationSaver.prototype.save.yields null, true
      @sut = new FlowDeployer @flow, { ConfigurationGenerator: ConfigurationGenerator, ConfigurationSaver: ConfigurationSaver }

    describe 'when deploy is called', ->
      beforeEach (done)->
        @sut.deploy  => done()

      it 'should call configuration saver with the configuration', ->
        expect(ConfigurationSaver.prototype.save).to.have.been.calledWith @configuration

    describe 'when deploy is called and the configuration generator returns an error', ->
      beforeEach (done)->
        ConfigurationGenerator.prototype.configure.yields new Error 'Oh noes'
        @sut.deploy  (@error, @result)=> done()

      it 'should return an error with an error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the configuration save returns an error', ->
      beforeEach (done)->
        ConfigurationGenerator.prototype.configure.yields null, { erik_likes_me: true}
        ConfigurationSaver.prototype.save.yields new Error 'Erik can never like me enough'
        @sut.deploy  (@error, @result)=> done()

      it 'should yield and error', ->
        expect(@error).to.exist

      it 'should not give us a result', ->
        expect(@result).to.not.exist

    describe 'when deploy is called and the generator and saver actually worked', ->
      beforeEach (done) ->
        ConfigurationGenerator.prototype.configure.yields null, { erik_likes_me: 'more than you know'}
        ConfigurationSaver.prototype.save.yields null, {finally_i_am_happy: true}

        @sut.deploy  (@error, @result) => done()

      it 'should not yield an error', ->
        expect(@error).to.not.exist


    describe 'setupDeviceForwarding', ->
      it 'should exist', ->
        expect(@sut.setupDeviceForwarding).to.exist

      it 'should update a meshblu device with the webhook to wherever it\'s going', ->
        #todo: monkey patch node virtual machine.
        expect(true).to.be.false



    describe 'startFlow', ->
      it 'should exist', ->
        expect(@sut.startFlow).to.exist

    describe 'stopFlow', ->
      it 'should exist', ->
        expect(@sut.stopFlow).to.exist
