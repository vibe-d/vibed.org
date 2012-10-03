import vibe.d;

import vibelog.vibelog;
import api;

import std.algorithm;
import std.array;
import std.datetime;


string[] s_moduleNames;
Json[string] s_modules;
Json[] s_projectTree;

void download(HttpServerRequest req, HttpServerResponse res)
{
	if( "file" in req.query )
		res.redirect("https://github.com/rejectedsoftware/vibe.d/"~req.query["file"]);
	else res.renderCompat!("download.dt", HttpServerRequest, "req")(Variant(req));
}

void showApi(HttpServerRequest req, HttpServerResponse res)
{
	struct Info2 {
		string[] moduleNames;
		Json[string] modules;
		Json[] projectTree;
	}
	Info2 info;

	info.moduleNames = s_moduleNames;
	info.modules = s_modules;
	info.projectTree = s_projectTree;

	res.renderCompat!("api.dt",
		HttpServerRequest, "req",
		Info2*, "info")
		(Variant(req), Variant(&info));
}

void showApiModule(HttpServerRequest req, HttpServerResponse res)
{
	struct Info2 {
		string[] moduleNames;
		Json[string] modules;
		Json[] projectTree;
		string moduleName;
	}
	Info2 info;

	info.moduleName = req.params["modulename"];
	info.moduleNames = s_moduleNames;
	info.modules = s_modules;
	info.projectTree = s_projectTree;

	auto pm = info.moduleName in s_modules;
	if( pm is null ) return;

	res.renderCompat!("api-module.dt",
		HttpServerRequest, "req",
		Info2*, "info")
		(Variant(req), Variant(&info));
}

void showApiItem(HttpServerRequest req, HttpServerResponse res)
{
	struct Info3 {
		string[] moduleNames;
		Json[string] modules;
		Json[] projectTree;
		string moduleName;
		Json item;
		Json overloads;
	}
	Info3 info;


	info.moduleName = req.params["modulename"];
	info.moduleNames = s_moduleNames;
	info.modules = s_modules;
	info.projectTree = s_projectTree;

	auto pm = info.moduleName in s_modules;
	if( pm is null ) return;

	auto itemsteps = req.params["itemname"].split(".");
	if( itemsteps.length == 0 ) return;

	info.item = *pm;
	info.overloads = *pm;
	foreach( i, st; itemsteps ){
		search:
		foreach( mcat; info.item.members )
			foreach( mem; mcat ){
				auto mcmp = mem.type == Json.Type.Array ? mem[0] : mem;
				if( mcmp.name == st ){
					info.item = mcmp;
					info.overloads = mem;
					break search;
				}
			}
	}

	switch( info.item.kind.get!string ){
		default: logWarn("Unknown API item kind: %s", info.item.kind.get!string); return;
		case "function":
			res.renderCompat!("api-function.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
		case "interface":
		case "class":
		case "struct":
			res.renderCompat!("api-class.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
		case "enum":
			res.renderCompat!("api-enum.dt", HttpServerRequest, "req", Info3*, "info")(Variant(req), Variant(&info));
			break;
	}
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
		//s_projectTree = cast(Json[])json;
		foreach( m; json ){
			auto mname = m.name.get!string;
			s_moduleNames ~= mname;
			s_modules[mname] = m;
		}
		s_moduleNames.sort();
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
	router.get("/templates", staticTemplate!"templates.dt");
	router.get("/api", staticRedirect("/api/"));
	router.get("/api/", &showApi);
	router.get("/api/:modulename", delegate(req, res){ res.redirect("/api/"~req.params["modulename"]~"/"); });
	router.get("/api/:modulename/", &showApiModule);
	router.get("/api/:modulename/:itemname", &showApiItem);

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibe.d";
	blogsettings.basePath = "/blog/";
	blogsettings.textFilters ~= &prettifyFilter;
	registerVibeLog(blogsettings, router);

	router.get("*", serveStaticFiles("./public/"));
	
	listenHttp(settings, router);
}
