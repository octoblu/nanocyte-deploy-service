FlowDeployer = require '../src/flow-deployer'
describe 'FlowDeployer', ->
  describe 'when constructed', ->
    beforeEach ->
      @sut = new FlowDeployer

    it 'should exist', ->
      expect(@sut).to.exist

  describe 'when constructed with a flow and a configurer', ->
    beforeEach ->
      @flow = {}
      @configuration = {}
      class ConfigurationGenerator
        configure: sinon.stub().yields @configuration

      class ConfigurationSaver
        process: sinon.stub()

      @sut = new FlowDeployer @flow, ConfigurationGenerator: ConfigurationGenerator, ConfigurationSaver: ConfigurationSaver

    describe 'when deploy is called', ->
      beforeEach ->
        @sut.deploy()
