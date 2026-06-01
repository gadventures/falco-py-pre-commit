sub vcl_recv {
    #FASTLY RECV
    set req.http.X-Smoke-Test = "ok";
}
