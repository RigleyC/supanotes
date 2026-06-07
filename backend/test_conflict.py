import http.client, json, uuid

BASE='localhost'
PORT=8080

def register(email):
    conn=http.client.HTTPConnection(BASE,PORT)
    payload={'name':'a','email':email,'password':'password'}
    conn.request('POST','/api/v1/auth/register',json.dumps(payload),{'Content-Type':'application/json'})
    res=conn.getresponse(); data=res.read().decode(); print('register',email,res.status,data)
    return res.status

def login(email):
    conn=http.client.HTTPConnection(BASE,PORT)
    conn.request('POST','/api/v1/auth/login',json.dumps({'email':email,'password':'password'}),{'Content-Type':'application/json'})
    res=conn.getresponse(); data=res.read().decode(); print('login',email,res.status,data)
    if res.status==200:
        return json.loads(data).get('access_token')
    return None


def push(token, payload):
    conn=http.client.HTTPConnection(BASE,PORT)
    headers={'Content-Type':'application/json'}
    if token:
        headers['Authorization']='Bearer '+token
    conn.request('POST','/api/v1/sync/push',json.dumps(payload),headers)
    res=conn.getresponse(); data=res.read().decode(); print('push',res.status,data)
    return res.status, data

id_str=str(uuid.uuid4())
note={'id':id_str,'title':'note1','content':'hello','is_inbox':False,'favorite':False,'archived':False,'created_at':'2026-06-05T00:00:00Z','updated_at':'2026-06-05T00:00:00Z'}

email1=f'usera_{id_str[:8]}@example.com'
email2=f'userb_{id_str[:8]}@example.com'
register(email1)
register(email2)

tok1=login(email1)
status1,_=push(tok1,{'notes':[note],'tasks':[],'contexts':[],'tags':[]})

tok2=login(email2)
status2,body2=push(tok2,{'notes':[note],'tasks':[],'contexts':[],'tags':[]})
print('results',status1,status2)
