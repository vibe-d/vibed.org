import vibe.d;

import vibelog.vibelog;

import ddox.ddox;
import ddox.entities;
import ddox.htmlserver;
import ddox.htmlgenerator;
import ddox.jsonparser;
import std.algorithm;
import std.array;
import std.datetime;


Package m_rootPackage;

void download(HttpServerRequest req, HttpServerResponse res)
{
	if( auto pf = "file" in req.query ){
		if( (*pf).startsWith("zipball") ) res.redirect("https://github.com/rejectedsoftware/vibe.d/" ~ *pf);
		else res.redirect("http://vibed.org/files/" ~ *pf);
	} else res.renderCompat!("download.dt", HttpServerRequest, "req")(Variant(req));
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
		settings.declSort = SortMode.Name;
		m_rootPackage = parseJsonDocs(json, settings);
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

	auto fsettings = new HttpFileServerSettings;
	fsettings.maxAge = 0;
	router.get("*", serveStaticFiles("./public/", fsettings));

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibe.d";
	blogsettings.siteUrl = Url("http://vibed.org/blog/");
	blogsettings.textFilters ~= &prettifyFilter;
	registerVibeLog(blogsettings, router);

	auto docsettings = new GeneratorSettings;
	docsettings.navigationType = NavigationType.ModuleTree;
	docsettings.siteUrl = Url("http://vibed.org/api");
	registerApiDocs(router, m_rootPackage, docsettings);

	listenHttp(settings, router);
}
