"""Keep published privacy detail when synchronizing the older standalone page.

These passages are copied from the in-app privacy template at release commit
 dbc5be973974caa0f17532c5cd0d3ea3ab031832 (index blob
 489eef6e9d50c75787c4783175fb0b54cd85cf3a).
They describe existing behavior; this module changes no permissions or records.
An unknown or mixed source fails instead of silently replacing a disclosure.
"""

OLD_FIELDS = 'medical or clearance documents; staff credentials, officials\' assignments, budgets, signed forms and feedback.'
FIELDS = 'medical or clearance documents; sports membership numbers, expiration dates, membership cards and athlete or staff credentials; officials\' assignments, budgets, signed forms and feedback.'
OLD_ORG = '<p>Authorized organization operations roles can access relevant roster information and guardian phone numbers within their assigned scope even when ordinary coach contact sharing is turned off. That operations roster excludes athlete phone numbers and email addresses, private weight history and medical documents.</p>'
ORG = '<p>Authorized organization operations roles can access relevant roster information and guardian phone numbers for teams managed by their organization, within their assigned scope, even when ordinary coach contact sharing is turned off. That operations roster excludes athlete phone numbers and email addresses, private weight history and medical documents.</p>'
MEMBERSHIP = '''<p>An independent team can approve an affiliation with another organization for membership support. Authorized membership-support staff can then see athlete names, sports membership numbers, expiration dates, membership status, uploaded membership cards and recorded credentials. This affiliation does not itself give access to guardian contacts, private weight history, medical records or team administration. Removing the affiliation ends that affiliation-based access.</p>
<p>Membership cards are stored privately. Membership and credential review labels record a person's review; they do not indicate an automatic check against USA Wrestling or another credential provider.</p>'''
PROFILES = '''<h2>Shared wrestling profiles and family invitations</h2>
<p>Profile discovery starts off. Approved shared fields may include a profile picture, wrestling roles, age division, tournament history and a music link. Following a profile does not grant messaging access or access to private team records. The outside-view preview shows shared member visibility; separately authorized team and family access can differ.</p>
<p>Family invitations must be claimed by a signed-in account and approved by the profile manager. Approved relatives receive view-only access to the selected shared profile fields and/or individually selected upcoming events, including event times and location names. Family access alone does not grant weights, medical documents, guardian authority, team administration or messaging. Newly created events are not automatically shared. Revoking access prevents future requests but cannot recall information already viewed; an issued profile-photo link can last up to 60 seconds.</p>'''


def _replace_once(text: str, old: str, new: str) -> str:
    if new in text:
        assert text.count(new) == 1 and old not in text, 'Mixed privacy disclosure variants'
        return text
    assert text.count(old) == 1, 'Unexpected source for preserved disclosure'
    return text.replace(old, new, 1)


def preserve_privacy(text: str) -> str:
    """Upgrade only known older passages and require every published detail."""
    text = _replace_once(text, OLD_FIELDS, FIELDS)
    text = _replace_once(text, OLD_ORG, ORG)
    if MEMBERSHIP not in text:
        assert 'An independent team can approve an affiliation' not in text, 'Changed membership disclosure needs review'
        assert 'Membership cards are stored privately.' not in text, 'Partial membership disclosure needs review'
        text = text.replace(ORG, ORG + '\n' + MEMBERSHIP, 1)
    if PROFILES not in text:
        assert 'Shared wrestling profiles and family invitations' not in text, 'Changed profile disclosure needs review'
        assert 'Profile discovery starts off.' not in text, 'Partial profile disclosure needs review'
        anchor = '<h2>Parent choices without an account</h2>'
        assert text.count(anchor) == 1, 'Missing profile insertion anchor'
        text = text.replace(anchor, PROFILES + '\n' + anchor, 1)
    for passage in (FIELDS, ORG, MEMBERSHIP, PROFILES):
        assert text.count(passage) == 1, 'Published privacy detail missing or duplicated'
    return text
