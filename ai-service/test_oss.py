import httpx, asyncio, os

DASHSCOPE_API_KEY = 'sk-31a894a2bf8e450c93dbd783230cd65a'
DASHSCOPE_BASE = 'https://dashscope.aliyuncs.com'

async def test():
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f'{DASHSCOPE_BASE}/api/v1/uploads',
            headers={'Authorization': f'Bearer {DASHSCOPE_API_KEY}'},
            params={'action': 'getPolicy', 'model': 'aitryon'},
        )
        print(f'Policy status: {resp.status_code}')
        policy_data = resp.json().get('data', {})
        if not policy_data:
            print(f'No policy data: {resp.text}')
            return
        print(f'Upload host: {policy_data.get("upload_host")}')
        print(f'Upload dir: {policy_data.get("upload_dir")}')

        local_path = 'e:/test/2/ai-service/uploads/test_person.png'
        filename = 'test_person2.png'
        key = f'{policy_data["upload_dir"]}/{filename}'

        with open(local_path, 'rb') as f:
            data = {
                'OSSAccessKeyId': policy_data['oss_access_key_id'],
                'Signature': policy_data['signature'],
                'policy': policy_data['policy'],
                'x-oss-object-acl': policy_data['x_oss_object_acl'],
                'x-oss-forbid-overwrite': policy_data['x_oss_forbid_overwrite'],
                'key': key,
                'success_action_status': '200',
            }
            files = {'file': (filename, f, 'image/png')}

            print(f'Key: {key}')
            upload_resp = await client.post(
                policy_data['upload_host'],
                data=data,
                files=files,
            )
            print(f'Upload status: {upload_resp.status_code}')
            print(f'Upload response: {upload_resp.text[:300]}')

if __name__ == '__main__':
    asyncio.run(test())