from routes import auth as auth_routes


def test_rate_limit_decorator_wraps_when_enabled(monkeypatch):
    monkeypatch.setattr(auth_routes, "is_testing", False)

    def dummy(request):
        return "ok"

    wrapped = auth_routes.rate_limit("1/minute")(dummy)
    assert wrapped is not dummy
