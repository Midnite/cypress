root          = "../../../"
Server        = require("#{root}lib/server")
Fixtures      = require "#{root}/spec/server/helpers/fixtures"
expect        = require("chai").expect
nock          = require('nock')
sinon         = require('sinon')
supertest     = require("supertest")
Session       = require("supertest-session")
str           = require("underscore.string")

removeWhitespace = (c) ->
  c = str.clean(c)
  c = str.lines(c).join(" ")
  c

describe "Routes", ->
  beforeEach ->
    nock.enableNetConnect()

    @sandbox = sinon.sandbox.create()
    @sandbox.stub(Server.prototype, "getCypressJson").returns({})

    @server = Server("/Users/brian/app")
    @server.configureApplication()

    @app    = @server.app
    @server.setCypressJson {
      projectRoot: "/Users/brian/app"
    }

    ## create a session which will store cookies
    ## in between session requests :-)
    @session = new (Session({app: @app}))

  afterEach ->
    @session.destroy()
    @sandbox.restore()
    nock.cleanAll()

  context "GET /", ->
    it "redirects to config.clientRoute", (done) ->
      supertest(@app)
      .get("/")
      .expect(302)
      .expect (res) ->
        expect(res.headers.location).to.eq "/__/"
        null
      .end(done)

  context "GET /__", ->
    it "routes config.clientRoute to serve cypress client app html", (done) ->
      supertest(@app)
        .get("/__")
        .expect(200)
        .expect(/App.start\(.+\)/)
        .end(done)

  context "GET /files", ->
    beforeEach ->
      Fixtures.scaffold("todos")

      @server.setCypressJson {
        projectRoot: Fixtures.project("todos")
        testFolder: "tests"
      }

    afterEach ->
      Fixtures.remove("todos")

    it "returns base json file path objects", (done) ->
      supertest(@app)
        .get("/files")
        .expect(200, [
          { name: "sub/sub_test.coffee" },
          { name: "test1.js" },
          { name: "test2.coffee" }
        ])
        .end(done)

    it "sets X-Files-Path header to the length of files", (done) ->
      filesPath = Fixtures.project("todos") + "/" + "tests"

      supertest(@app)
        .get("/files")
        .expect(200)
        .expect("X-Files-Path", filesPath)
        .end(done)

  context "GET /iframes/*", ->
    beforeEach ->
      Fixtures.scaffold("todos")

      @server.setCypressJson {
        projectRoot: Fixtures.project("todos")
        testFolder: "tests"
        sinon: false
        fixtures: false
      }

    afterEach ->
      Fixtures.remove("todos")

    it "renders empty inject with variables passed in", (done) ->
      contents = removeWhitespace Fixtures.get("server/expected_empty_inject.html")

      supertest(@app)
        .get("/iframes/test2.coffee")
        .expect(200)
        .expect (res) ->
          body = removeWhitespace(res.text)
          expect(body).to.eq contents
          null
        .end(done)

  context "GET /__remote/*", ->
    describe "?__initial=true", ->
      beforeEach ->
        ## reconfigure app routes each test
        @server.configureApplication()

        @baseUrl = "http://www.github.com"

      it "basic 200 html response", (done) ->
        nock(@baseUrl)
          .get("/bar")
          .reply 200, "hello from bar!", {
            "Content-Type": "text/html"
          }

        supertest(@app)
          .get("/__remote/#{@baseUrl}/bar?__initial=true")
          .expect(200, "hello from bar!")
          .end(done)

      it "injects sinon content into head", (done) ->
        contents = removeWhitespace Fixtures.get("server/expected_sinon_inject.html")

        nock(@baseUrl)
          .get("/bar")
          .reply 200, "<html> <head> <title>foo</title> </head> <body>hello from bar!</body> </html>", {
            "Content-Type": "text/html"
          }

        supertest(@app)
          .get("/__remote/#{@baseUrl}/bar?__initial=true")
          .expect(200)
          .expect (res) ->
            body = removeWhitespace(res.text)
            expect(body).to.eq contents
            null
          .end(done)

      it "injects sinon content after following redirect", (done) ->
        contents = removeWhitespace Fixtures.get("server/expected_sinon_inject.html")

        nock(@baseUrl)
          .log(console.log)
          .get("/bar")
          .reply 302, undefined, {
            "Location": @baseUrl + "/foo"
          }
          .get("/foo")
          .reply 200, "<html> <head> <title>foo</title> </head> <body>hello from bar!</body> </html>", {
            "Content-Type": "text/html"
          }

        supertest(@app)
          .get("/__remote/#{@baseUrl}/bar?__initial=true")
          .expect(302)
          .expect "location", "/__remote/http://www.github.com/foo?__initial=true"
          .end (err, res) =>
            return done(err) if err

            supertest(@app)
              .get(res.headers.location)
              .expect(200)
              .expect (res) ->
                body = removeWhitespace(res.text)
                expect(body).to.eq contents
                null
              .end(done)

      context "error handling", ->
        it "status code 500", (done) ->
          nock(@baseUrl)
            .get("/index.html")
            .reply(500)

          supertest(@app)
            .get("/__remote/#{@baseUrl}/index.html?__initial=true")
            .expect(500)
            .end(done)

        it "sends back initial_500 content", (done) ->
          nock(@baseUrl)
            .get("/index.html")
            .reply(500)

          supertest(@app)
            .get("/__remote/#{@baseUrl}/index.html?__initial=true")
            .expect (res) ->
              expect(res.text).to.include("<span data-cypress-visit-error></span>")
              null
            .end(done)

      context "headers", ->
        it "forwards headers on outgoing requests", (done) ->
          nock(@baseUrl)
          .get("/bar")
          .matchHeader("x-custom", "value")
          .reply 200, "hello from bar!", {
            "Content-Type": "text/html"
          }

          supertest(@app)
            .get("/__remote/#{@baseUrl}/bar?__initial=true")
            .set("x-custom", "value")
            .expect(200, "hello from bar!")
            .end(done)

        it "omits forwarding host header", (done) ->
          nock(@baseUrl)
          .matchHeader "host", (val) ->
            val isnt "demo.com"
          .get("/bar")
          .reply 200, "hello from bar!", {
            "Content-Type": "text/html"
          }

          supertest(@app)
            .get("/__remote/#{@baseUrl}/bar?__initial=true")
            .set("host", "demo.com")
            .expect(200, "hello from bar!")
            .end(done)

        it "omits forwarding accept-encoding", (done) ->
          nock(@baseUrl)
          .matchHeader "accept-encoding", (val) ->
            val isnt "foo"
          .get("/bar")
          .reply 200, "hello from bar!", {
            "Content-Type": "text/html"
          }

          supertest(@app)
            .get("/__remote/#{@baseUrl}/bar?__initial=true")
            .set("host", "demo.com")
            .set("accept-encoding", "foo")
            .expect(200, "hello from bar!")
            .end(done)

        it "omits forwarding accept-language", (done) ->
          nock(@baseUrl)
          .matchHeader "accept-language", (val) ->
            val isnt "utf-8"
          .get("/bar")
          .reply 200, "hello from bar!", {
            "Content-Type": "text/html"
          }

          supertest(@app)
            .get("/__remote/#{@baseUrl}/bar?__initial=true")
            .set("host", "demo.com")
            .set("accept-language", "utf-8")
            .expect(200, "hello from bar!")
            .end(done)

    describe "when session is already set", ->
      context "absolute baseUrl", ->
        beforeEach (done) ->
          @baseUrl = "http://getbootstrap.com"

          ## make an initial request to set the
          ## session proxy!
          nock("/__remote/#{@baseUrl}")
            .get("/css")
            .reply 200, "content page", {
              "Content-Type": "text/html"
            }

          @session
            .get("/__remote/#{@baseUrl}/css?__initial=true")
            .expect (res) ->
              expect(res.get("set-cookie")[0]).to.include("__cypress.sid")
              null
            .end(done)

        it "proxies absolute requests", (done) ->
          nock(@baseUrl)
            .get("/assets/css/application.css")
            .reply 200, "html { color: #333 }", {
              "Content-Type": "text/css"
            }

          @session
            .get("/__remote/#{@baseUrl}/assets/css/application.css")
            .expect(200, "html { color: #333 }")
            .end(done)

      context "relative baseUrl", ->
        beforeEach (done) ->
          ## we no longer server initial content from the rootFolder
          ## and it would be suggested for this project to be configured
          ## with a baseUrl of "dev/", which would automatically be
          ## appended to cy.visit("/index.html")
          @baseUrl = "dev/index.html"

          Fixtures.scaffold("no-server")

          @server.setCypressJson {
            projectRoot: Fixtures.project("no-server")
            rootFolder: "dev"
            testFolder: "my-tests"
          }

          @session
            .get("/__remote/#{@baseUrl}?__initial=true")
            .expect(200)
            .expect(/index.html content/)
            .expect (res) ->
              expect(res.get("set-cookie")[0]).to.include("__cypress.sid")
              null
            .end(done)

        afterEach ->
          Fixtures.remove("no-server")

        it "streams from file system", (done) ->
          @session
            .get("/__remote/assets/app.css")
            .expect(200, "html { color: black; }")
            .end(done)

  context "GET *", ->
    beforeEach (done) ->
      @baseUrl = "http://getbootstrap.com"

      ## make an initial request to set the
      ## session proxy!
      nock(@baseUrl)
        .get("/css")
        .reply 200, "css content page", {
          "Content-Type": "text/html"
        }

      @session
        .get("/__remote/#{@baseUrl}/css?__initial=true")
        .expect (res) ->
          expect(res.get("set-cookie")[0]).to.include("__cypress.sid")
          null
        .end(done)

    it "proxies to the remote session", (done) ->
      nock(@baseUrl)
        .get("/assets/css/application.css")
        .reply 200, "html { color: #333 }", {
          "Content-Type": "text/css"
        }

      @session
        .get("/assets/css/application.css")
        .expect(200, "html { color: #333 }")
        .end(done)