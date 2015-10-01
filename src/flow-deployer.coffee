_ = require 'lodash'
async = require 'async'
FLOW_START_NODE = 'engine-start'
FLOW_STOP_NODE = 'engine-stop'
MeshbluConfig = require 'meshblu-config'
FlowStatusMessenger = require './flow-status-messenger'

class FlowDeployer
  constructor: (options, dependencies={}) ->
    {@flowUuid, @instanceId, @flowToken, @forwardUrl, @userUuid, @userToken, @octobluUrl, @deploymentUuid} = options
    {@flowLoggerUuid} = options
    {@configurationSaver, @configurationGenerator, MeshbluHttp, @request} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    @request ?= require 'request'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUuid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

    @flowStatusMessenger = new FlowStatusMessenger @meshbluHttp,
      userUuid: @userUuid
      flowUuid: @flowUuid
      workflow: 'flow-start'
      deploymentUuid: @deploymentUuid
      flowLoggerUuid: @flowLoggerUuid

  deploy: (callback=->) =>
    @flowStatusMessenger.message 'begin'
    @getFlowAndUserData (error, results) =>
      @flowStatusMessenger.message 'error', error.message if error?
      return callback error if error?

      results.flowToken = @flowToken
      results.deploymentUuid = @deploymentUuid

      @configurationGenerator.configure results, (error, config, stopConfig) =>
        @flowStatusMessenger.message 'error', error.message if error?
        return callback error if error?

        @clearAndSaveConfig config: config, stopConfig: stopConfig, (error) =>
          @flowStatusMessenger.message 'error', error.message if error?
          return callback error if error?

          @setupDeviceForwarding (error) =>
            @flowStatusMessenger.message 'error', error.message if error?
            @flowStatusMessenger.message 'end' unless error?
            callback error

  destroy: (callback=->) =>
    @configurationSaver.stop flowId: @flowUuid, callback

  clearAndSaveConfig: (options, callback) =>
    {config, stopConfig} = options

    saveOptions =
      flowId: @flowUuid
      instanceId: @instanceId
      flowData: config

    saveStopOptions =
      flowId: "#{@flowUuid}-stop"
      instanceId: @instanceId
      flowData: stopConfig

    async.series [
      async.apply @configurationSaver.stop, flowId: @flowUuid
      async.apply @configurationSaver.save, saveOptions
      async.apply @configurationSaver.save, saveStopOptions
    ], callback

  getFlowAndUserData: (callback) =>
    async.parallel
      userData: async.apply @_get, "#{@octobluUrl}/api/user"
      flowData: async.apply @_get, "#{@octobluUrl}/api/flows/#{@flowUuid}"
    , callback

  _get: (url, callback)=>
    options =
      json: true
      auth:
        user: @userUuid
        pass: @userToken

    @request.get url, options, (error, response, body) =>
      callback error, body

  setupDeviceForwarding: (callback=->) =>
    messageHook =
      url: @forwardUrl
      method: 'POST'
      generateAndForwardMeshbluCredentials: true
      name: 'nanocyte-flow-deploy'

    removeOldMessageHooks =
      $pull: 'meshblu.messageHooks': {name: messageHook.name}

    addNewMessageHooks =
      $addToSet: 'meshblu.messageHooks': messageHook

    async.series [
      async.apply @meshbluHttp.updateDangerously, @flowUuid, removeOldMessageHooks
      async.apply @meshbluHttp.updateDangerously, @flowUuid, addNewMessageHooks
    ], callback

  startFlow: (callback=->) =>
    message =
      devices: [@flowUuid]
      payload:
        from: FLOW_START_NODE

    _.defer @flowStatusMessenger.message, 'begin', undefined, application: 'flow-runner'
    async.series [
      async.apply @meshbluHttp.updateDangerously, @flowUuid, $set: {online: true, deploying: false, stopping: false}
      async.apply @meshbluHttp.message, message
    ], callback

  stopFlow: (callback=->) =>
    message =
      devices: [@flowUuid]
      payload:
        from: FLOW_STOP_NODE

    async.series [
      async.apply @meshbluHttp.updateDangerously, @flowUuid, $set: {online: false, deploying: false, stopping: false}
      async.apply @meshbluHttp.message, message
    ], callback

module.exports = FlowDeployer
