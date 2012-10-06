import vibe.d;

import vibelog.vibelog;

import ddox.ddox;
import ddox.entities;
import ddox.htmlserver;
import ddox.jsonparser;
import std.algorithm;
import std.array;
import std.datetime;


Package m_rootPackage;

void download(HttpServerRequest req, HttpServerResponse res)
{
	if( "file" in req.query )
		res.redirect("https://github.com/rejectedsoftware/vibe.d/"~req.query["file"]);
	else res.renderCompat!("download.dt", HttpServerRequest, "req")(Variant(req));
}

void error(HttpServerRequest req, HttpServerResponse res, HttpServerErrorInfo error)
{
	res.renderCompat!("error.dt",
		HttpServerRequest, "req",
		HttpServerErrorInfo, "error")
		(Variant(req), Variant(error));
}

void updateDocs()
{
	try { 
		import std.file;
		string text = readText("docs.json");
		auto json = parseJson(text);
		auto settings = new DdoxSettings;
		m_rootPackage = parseJsonDocs(json, settings);
		//m_rootPackage = loaDdox(json);
	} catch( Exception e ){
		logError("Error loading docs: %s", e.toString());
		throw e;
	}
}

string prettifyFilter(string html)
{
	return html.replace("<code><pre>", "<code><pre class=\"prettyprint\">");
}

static this()
{
	setLogLevel(LogLevel.None);
	setLogFile("log.txt", LogLevel.Info);

	updateDocs();

	auto settings = new HttpServerSettings;
	settings.hostName = "vibed.org";
	settings.port = 8003;
	settings.bindAddresses = ["127.0.0.1"];
	settings.errorPageHandler = toDelegate(&error);
	
	auto router = new UrlRouter;
	
	router.get("/",          staticTemplate!"home.dt");
	router.get("/about",     staticTemplate!"about.dt");
	router.get("/contact",   staticTemplate!"contact.dt");
	router.get("/community", staticTemplate!"community.dt");
	router.get("/impressum", staticTemplate!"impressum.dt");
	router.get("/download",  &download);
	router.get("/features",  staticTemplate!"features.dt");
	router.get("/docs",      staticTemplate!"docs.dt");
	router.get("/developer", staticTemplate!"developer.dt");
	router.get("/templates", staticRedirect("/templates/"));
	router.get("/templates/", staticRedirect("/templates/diet"));
	router.get("/templates/diet", staticTemplate!"templates.dt");

	registerApiDocs(router, m_rootPackage, "/api", false);

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibe.d";
	blogsettings.basePath = "/blog/";
	blogsettings.textFilters ~= &prettifyFilter;
	registerVibeLog(blogsettings, router);

	router.get("*", serveStaticFiles("./public/"));
	
	listenHttp(settings, router);
}
