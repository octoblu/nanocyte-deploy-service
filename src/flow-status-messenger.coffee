class FlowStatusMessenger
  constructor: (meshbluHttp, options={}) ->
    @meshbluHttp = meshbluHttp
    {@userUuid, @flowUuid, @workflow, @deploymentUuid, @flowLoggerUuid} = options

  message: (state,message,overrides={},callback=->) =>
    {application} = overrides
    application ?= 'flow-deploy-service'

    @meshbluHttp.message
      devices: [@flowLoggerUuid]
      payload:
        application: application
        date: Date.now()
        deploymentUuid: @deploymentUuid
        flowUuid: @flowUuid
        userUuid: @userUuid
        workflow: @workflow
        state:    state
        message:  message
    , callback

module.exports = FlowStatusMessenger
