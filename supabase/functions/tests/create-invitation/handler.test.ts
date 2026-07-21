import {
  createInvitation,
  type InvitationRepository,
} from '../../create-invitation/handler.ts'

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJSON = JSON.stringify(actual)
  const expectedJSON = JSON.stringify(expected)
  if (actualJSON !== expectedJSON) {
    throw new Error(`Expected ${expectedJSON}, received ${actualJSON}`)
  }
}

function fakeRepository(overrides: Partial<InvitationRepository> = {}): InvitationRepository {
  return {
    invitationIsAvailable: async () => true,
    createAndAudit: async () => ({
      invitationId: '11111111-1111-1111-1111-111111111111',
      expiresAt: '2026-07-24T00:00:00Z',
      usesExistingAuthUser: false,
    }),
    sendAuthInvitation: async () => {},
    revokeAfterDeliveryFailure: async () => {},
    ...overrides,
  }
}

Deno.test('rejects a caller without reviewer role', async () => {
  let checkedTarget = false
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'member@example.com' },
    {
      actor: { userId: crypto.randomUUID(), role: 'member', status: 'approved' },
      repository: fakeRepository({
        invitationIsAvailable: async () => {
          checkedTarget = true
          return true
        },
      }),
    },
  )

  assertEquals(response, { ok: false, status: 403, code: 'not_authorized' })
  assertEquals(checkedTarget, false)
})

Deno.test('normalizes email before creating and sending an invitation', async () => {
  let createdEmail = ''
  let deliveredEmail = ''
  let checkedEmail = ''
  const response = await createInvitation(
    { targetPersonId: '22222222-2222-2222-2222-222222222222', email: '  Member@Example.COM ' },
    {
      actor: { userId: '33333333-3333-3333-3333-333333333333', role: 'trusted_elder', status: 'approved' },
      repository: fakeRepository({
        invitationIsAvailable: async (_personId, normalizedEmail) => {
          checkedEmail = normalizedEmail
          return true
        },
        createAndAudit: async (input) => {
          createdEmail = input.normalizedEmail
          return {
            invitationId: '11111111-1111-1111-1111-111111111111',
            expiresAt: '2026-07-24T00:00:00Z',
            usesExistingAuthUser: false,
          }
        },
        sendAuthInvitation: async (email) => {
          deliveredEmail = email
        },
      }),
    },
  )

  assertEquals(createdEmail, 'member@example.com')
  assertEquals(checkedEmail, 'member@example.com')
  assertEquals(deliveredEmail, 'member@example.com')
  assertEquals(response, {
    ok: true,
    status: 201,
    invitationId: '11111111-1111-1111-1111-111111111111',
    expiresAt: '2026-07-24T00:00:00Z',
    usesExistingAuthUser: false,
  })
})

Deno.test('rejects invalid email before accessing the repository', async () => {
  let accessedRepository = false
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'not-an-email' },
    {
      actor: { userId: crypto.randomUUID(), role: 'admin', status: 'approved' },
      repository: fakeRepository({
        invitationIsAvailable: async () => {
          accessedRepository = true
          return true
        },
      }),
    },
  )

  assertEquals(response, { ok: false, status: 400, code: 'invalid_email' })
  assertEquals(accessedRepository, false)
})

Deno.test('rejects a non-UUID target before accessing the repository', async () => {
  let accessedRepository = false
  const response = await createInvitation(
    { targetPersonId: 'not-a-uuid', email: 'member@example.com' },
    {
      actor: { userId: crypto.randomUUID(), role: 'admin', status: 'approved' },
      repository: fakeRepository({
        invitationIsAvailable: async () => {
          accessedRepository = true
          return true
        },
      }),
    },
  )

  assertEquals(response, { ok: false, status: 400, code: 'invalid_request' })
  assertEquals(accessedRepository, false)
})

Deno.test('rejects an unavailable target without sending email', async () => {
  let sentEmail = false
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'member@example.com' },
    {
      actor: { userId: crypto.randomUUID(), role: 'admin', status: 'approved' },
      repository: fakeRepository({
        invitationIsAvailable: async () => false,
        sendAuthInvitation: async () => {
          sentEmail = true
        },
      }),
    },
  )

  assertEquals(response, { ok: false, status: 409, code: 'target_unavailable' })
  assertEquals(sentEmail, false)
})

Deno.test('revokes a created invitation when email delivery fails', async () => {
  let revokedInvitationID = ''
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'member@example.com' },
    {
      actor: { userId: crypto.randomUUID(), role: 'admin', status: 'approved' },
      repository: fakeRepository({
        sendAuthInvitation: async () => {
          throw new Error('provider unavailable')
        },
        revokeAfterDeliveryFailure: async (invitationID) => {
          revokedInvitationID = invitationID
        },
      }),
    },
  )

  assertEquals(revokedInvitationID, '11111111-1111-1111-1111-111111111111')
  assertEquals(response, { ok: false, status: 409, code: 'delivery_failed' })
})

Deno.test('uses OTP delivery when a closed Auth identity is reactivated', async () => {
  let usedExistingAuthUser = false
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'returning@example.com' },
    {
      actor: { userId: crypto.randomUUID(), role: 'admin', status: 'approved' },
      repository: fakeRepository({
        createAndAudit: async () => ({
          invitationId: '11111111-1111-1111-1111-111111111111',
          expiresAt: '2026-07-24T00:00:00Z',
          usesExistingAuthUser: true,
        }),
        sendAuthInvitation: async (_email, _invitationId, usesExisting) => {
          usedExistingAuthUser = usesExisting
        },
      }),
    },
  )

  assertEquals(usedExistingAuthUser, true)
  assertEquals(response, {
    ok: true,
    status: 201,
    invitationId: '11111111-1111-1111-1111-111111111111',
    expiresAt: '2026-07-24T00:00:00Z',
    usesExistingAuthUser: true,
  })
})
