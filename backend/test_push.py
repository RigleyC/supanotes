import http.client, json, uuid
conn=http.client.HTTPConnection('localhost',8080)
name='t'
u=str(uuid.uuid4())[:8]
reg={'name':name,'email':f'{u}@example.com','password':'password'}
conn.request('POST','/api/v1/auth/register',json.dumps(reg),{'Content-Type':'application/json'})
res=conn.getresponse(); print('register',res.status,res.read().decode())
conn.request('POST','/api/v1/auth/login',json.dumps({'email':reg['email'],'password':reg['password']}),{'Content-Type':'application/json'})
res=conn.getresponse(); data=res.read().decode(); print('login',res.status,data)
try:
    j=json.loads(data)
    token=j.get('access_token') or j.get('token')
except:
    token=None
headers={'Content-Type':'application/json'}
if token:
    headers['Authorization']='Bearer '+token
payload={'notes':[],'tasks':[],'contexts':[],'tags':[]}
conn.request('POST','/api/v1/sync/push',json.dumps(payload),headers)
res=conn.getresponse(); print('push',res.status,res.read().decode())
