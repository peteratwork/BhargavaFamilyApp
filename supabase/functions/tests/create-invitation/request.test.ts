import { parseInvitationRequest } from '../../create-invitation/request.ts'

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJSON = JSON.stringify(actual)
  const expectedJSON = JSON.stringify(expected)
  if (actualJSON !== expectedJSON) {
    throw new Error(`Expected ${expectedJSON}, received ${actualJSON}`)
  }
}

Deno.test('returns invalid_request for malformed JSON', async () => {
  const request = new Request('https://example.test/create-invitation', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{',
  })

  assertEquals(await parseInvitationRequest(request), {
    ok: false,
    code: 'invalid_request',
  })
})

Deno.test('returns typed input for a valid request', async () => {
  const request = new Request('https://example.test/create-invitation', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      targetPersonId: '11111111-1111-1111-1111-111111111111',
      email: 'member@example.com',
    }),
  })

  assertEquals(await parseInvitationRequest(request), {
    ok: true,
    input: {
      targetPersonId: '11111111-1111-1111-1111-111111111111',
      email: 'member@example.com',
    },
  })
})
