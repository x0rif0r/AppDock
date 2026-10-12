"""Validate public catalog structure; authenticity requires human review."""
import datetime,json,pathlib,urllib.parse
root=pathlib.Path(__file__).resolve().parents[1]
data=json.loads((root/'catalog/apps.json').read_text())
assert data['schemaVersion']==1
datetime.date.fromisoformat(data['updatedOn'])
seen=set()
for app in data['apps']:
    assert type(app['id']) is int and app['id']>0 and app['id'] not in seen, 'Invalid/duplicate ID'
    seen.add(app['id'])
    assert app['name'].strip() and app['family'].strip()
    assert app['verification'] in ['reported','metadata_only','confirmed']
    assert app['distribution'] in ['unknown','listed','delisted']
    assert app['bundleID'] is None or isinstance(app['bundleID'],str) and '.' in app['bundleID'] and not any(c.isspace() for c in app['bundleID'])
    assert isinstance(app['aliases'],list) and all(isinstance(a,str) for a in app['aliases'])
    datetime.date.fromisoformat(app['checkedOn'])
    assert app['sources'] and all(urllib.parse.urlsplit(s).scheme=='https' and urllib.parse.urlsplit(s).hostname and not urllib.parse.urlsplit(s).username for s in app['sources'])
    assert set(app)<={'id','name','family','bundleID','aliases','verification','distribution','sources','checkedOn','notes','firstPublished','removedOn'},'Unsupported/private field'
print(f'Catalog valid: {len(seen)} unique app IDs. Authenticity is not automatically verified.')

unresolved=json.loads((root/'catalog/unresolved.json').read_text())
assert unresolved['schemaVersion']==1
datetime.date.fromisoformat(unresolved['updatedOn'])
bundles=set()
for app in unresolved['apps']:
    assert app['appStoreID'] is None, 'Unresolved identifiers must never trigger downloads'
    assert app['bundleID'] not in bundles and '.' in app['bundleID']
    bundles.add(app['bundleID'])
    assert set(app)<={'name','storeName','bundleID','family','appStoreID','candidateAppStoreID','notes','sources'},'Unsupported/private unresolved field'
    if 'candidateAppStoreID' in app: assert type(app['candidateAppStoreID']) is int and app['candidateAppStoreID']>0
print(f'Unresolved catalog valid: {len(bundles)} bundles; no download IDs assigned.')
