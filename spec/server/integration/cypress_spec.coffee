require("../spec_helper")

Fixtures = require("../helpers/fixtures")
api      = require("#{root}lib/api")
user     = require("#{root}lib/user")
errors   = require("#{root}lib/errors")
cypress  = require("#{root}lib/cypress")
Project  = require("#{root}lib/project")

describe "lib/cypress", ->
  beforeEach ->
    Fixtures.scaffold()
    @todosPath = Fixtures.projectPath("todos")

    ## force cypress to call directly into main without
    ## spawning a separate process
    @sandbox.stub(cypress, "isCurrentlyRunningElectron").returns(true)
    @sandbox.stub(process, "exit")
    @sandbox.spy(errors, "log")

    @expectExitWith = (code) =>
      expect(process.exit).to.be.calledWith(code)

    @expectExitWithErr = (type, msg) ->
      expect(errors.log).to.be.calledWithMatch({type: type})
      expect(process.exit).to.be.calledWith(1)
      if msg
        err = errors.log.getCall(0).args[0]
        expect(err.message).to.include(msg)

  afterEach ->
    Fixtures.remove()

  after ->
    mockery.disable()

  context "--get-key", ->
    it "writes out key and exits on success", ->
      Promise.all([
        user.set({name: "brian", session_token: "session-123"}),

        Project.add(@todosPath).then (id) =>
          @projectId = id
      ])
      .then =>
        @sandbox.spy(console, "log")
        @sandbox.stub(api, "getProjectToken")
          .withArgs(@projectId, "session-123")
          .resolves("new-key-123")

        cypress.start(["--get-key", "--project=#{@todosPath}"]).then =>
          expect(console.log).to.be.calledWith("new-key-123")
          @expectExitWith(0)

    it "logs error and exits when user isn't logged in", ->
      user.set({})
      .then =>
        cypress.start(["--get-key", "--project=#{@todosPath}"]).then =>
          @expectExitWithErr("NOT_LOGGED_IN")

    it "logs error and exits when project does not have an id", ->
      @pristinePath = Fixtures.projectPath("pristine")

      user.set({session_token: "session-123"})
      .then =>
        cypress.start(["--get-key", "--project=#{@pristinePath}"]).then =>
          @expectExitWithErr("NO_PROJECT_ID", @pristinePath)

    it "logs error and exits when project could not be found at the path", ->
      user.set({session_token: "session-123"})
      .then =>
        cypress.start(["--get-key", "--project=path/to/no/project"]).then =>
          @expectExitWithErr("NO_PROJECT_FOUND_AT_PROJECT_ROOT", "path/to/no/project")

    it "logs error and exits when project token cannot be fetched", ->
      Promise.all([
        user.set({session_token: "session-123"}),

        Project.add(@todosPath).then (id) =>
          @projectId = id
      ])
      .then =>
        @sandbox.stub(api, "getProjectToken")
          .withArgs(@projectId, "session-123")
          .rejects(new Error)

        cypress.start(["--get-key", "--project=#{@todosPath}"]).then =>
          @expectExitWithErr("CANNOT_FETCH_PROJECT_TOKEN")

  context "--new-key", ->
    it "writes out key and exits on success", ->
      Promise.all([
        user.set({name: "brian", session_token: "session-123"}),

        Project.add(@todosPath).then (id) =>
          @projectId = id
      ])
      .then =>
        @sandbox.spy(console, "log")
        @sandbox.stub(api, "updateProjectToken")
          .withArgs(@projectId, "session-123")
          .resolves("new-key-123")

        cypress.start(["--new-key", "--project=#{@todosPath}"]).then =>
          expect(console.log).to.be.calledWith("new-key-123")
          @expectExitWith(0)

    it "logs error and exits when user isn't logged in", ->
      user.set({})
      .then =>
        cypress.start(["--new-key", "--project=#{@todosPath}"]).then =>
          @expectExitWithErr("NOT_LOGGED_IN")

    it "logs error and exits when project does not have an id", ->
      @pristinePath = Fixtures.projectPath("pristine")

      user.set({session_token: "session-123"})
      .then =>
        cypress.start(["--new-key", "--project=#{@pristinePath}"]).then =>
          @expectExitWithErr("NO_PROJECT_ID", @pristinePath)

    it "logs error and exits when project could not be found at the path", ->
      user.set({session_token: "session-123"})
      .then =>
        cypress.start(["--new-key", "--project=path/to/no/project"]).then =>
          @expectExitWithErr("NO_PROJECT_FOUND_AT_PROJECT_ROOT", "path/to/no/project")

    it "logs error and exits when project token cannot be fetched", ->
      Promise.all([
        user.set({session_token: "session-123"}),

        Project.add(@todosPath).then (id) =>
          @projectId = id
      ])
      .then =>
        @sandbox.stub(api, "updateProjectToken")
          .withArgs(@projectId, "session-123")
          .rejects(new Error)

        cypress.start(["--new-key", "--project=#{@todosPath}"]).then =>
          @expectExitWithErr("CANNOT_CREATE_PROJECT_TOKEN")



