import http.client, json, sys, uuid
email = f'test-sync-{uuid.uuid4().hex[:8]}@supanotes.io'
conn = http.client.HTTPConnection('localhost', 8080)
payload = json.dumps({'email':email,'password':'password123','name':'Test Sync'})
conn.request('POST','/api/v1/auth/register',payload,{'Content-Type':'application/json'})
res = conn.getresponse(); data = res.read().decode(); print('register', res.status, data)
if res.status != 201:
    sys.exit(1)
obj = json.loads(data)
token = obj['access_token']
conn = http.client.HTTPConnection('localhost', 8080)
payload = json.dumps({'notes':[{'id':'11111111-1111-1111-1111-111111111111','context_id':None,'title':'Test','content':'Hello','excerpt':None,'is_inbox':False,'favorite':False,'archived':False,'embedding_status':'','created_at':'2024-06-05T12:00:00Z','updated_at':'2024-06-05T12:00:00Z','deleted_at':None}],'tasks':[],'contexts':[],'tags':[]})
conn.request('POST','/api/v1/sync/push',payload,{'Content-Type':'application/json','Authorization':'Bearer '+token})
res = conn.getresponse(); data = res.read().decode(); print('push', res.status, data)
