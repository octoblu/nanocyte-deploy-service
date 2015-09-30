_ = require 'lodash'
async = require 'async'
FLOW_START_NODE = 'engine-start'
FLOW_STOP_NODE = 'engine-stop'
MeshbluConfig = require 'meshblu-config'

class FlowDeployer
  constructor: (@options, dependencies={}) ->
    {@flowUuid, @instanceId, @flowToken, @forwardUrl, @userUuid, @userToken, @octobluUrl, @deploymentUuid} = @options
    {@configurationSaver, @configurationGenerator, MeshbluHttp, @request} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    @request ?= require 'request'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUuid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

  deploy: (callback=->) =>
    @getFlowAndUserData (error, results) =>
      return callback error if error?

      results.flowToken = @flowToken
      results.deploymentUuid = @deploymentUuid

      @configurationGenerator.configure results, (error, config, stopConfig) =>
        return callback error if error?

        @clearAndSaveConfig config: config, stopConfig: stopConfig, (error) =>
          return callback error if error?

          @setupDeviceForwarding callback

  destroy: (callback=->) =>
    @configurationSaver.stop flowId: @flowUuid

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
