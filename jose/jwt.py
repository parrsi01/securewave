import jwt as pyjwt


def encode(payload, key, algorithm="HS256", headers=None):
    return pyjwt.encode(payload, key, algorithm=algorithm, headers=headers)


def decode(
    token,
    key,
    algorithms=None,
    options=None,
    audience=None,
    issuer=None,
    subject=None,
    leeway=0,
):
    kwargs = {
        "algorithms": algorithms,
        "options": options,
        "audience": audience,
        "issuer": issuer,
        "leeway": leeway,
    }
    if subject is not None:
        kwargs["subject"] = subject
    return pyjwt.decode(token, key, **kwargs)
