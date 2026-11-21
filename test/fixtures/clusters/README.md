# Golden clustering fixture — one launch, three sources

`inkling-launch.json` is one event as three sources would carry it: a Hacker
News submission (with campaign parameters on the URL), the company blog post,
and a social post. The clustering must make one story of them, and the test
pins the roles.

The HN and blog entries are modelled on the real Inkling 2 Mini launch, which
appears in the recorded HN and Hugging Face payloads. The social entry is the
shape a Bluesky adapter will produce — there is no Bluesky adapter yet
(`docs/PLAN.md` puts it with phase 3's cluster inputs), so it is written here
rather than recorded.
