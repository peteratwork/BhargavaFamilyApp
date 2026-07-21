export type AccountRole = 'member' | 'trusted_elder' | 'admin'

export type Actor = {
  userId: string
  role: AccountRole
  status: string
}

export type CreateInvitationInput = {
  targetPersonId: string
  email: string
}

export type CreatedInvitation = {
  invitationId: string
  expiresAt: string
}

export interface InvitationRepository {
  targetIsAvailable(personId: string): Promise<boolean>
  createAndAudit(input: {
    targetPersonId: string
    normalizedEmail: string
    actorUserId: string
  }): Promise<CreatedInvitation>
  sendAuthInvitation(email: string, invitationId: string): Promise<void>
  revokeAfterDeliveryFailure(invitationId: string): Promise<void>
}

export type CreateInvitationResult =
  | ({ ok: true; status: 201 } & CreatedInvitation)
  | {
      ok: false
      status: 400 | 403 | 409
      code: 'invalid_email' | 'not_authorized' | 'target_unavailable' | 'delivery_failed'
    }

const emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

export async function createInvitation(
  input: CreateInvitationInput,
  dependencies: { actor: Actor; repository: InvitationRepository },
): Promise<CreateInvitationResult> {
  const email = input.email.trim().toLocaleLowerCase('en-US')

  if (!emailPattern.test(email)) {
    return { ok: false, status: 400, code: 'invalid_email' }
  }

  const canReview = dependencies.actor.status === 'approved' &&
    (dependencies.actor.role === 'trusted_elder' || dependencies.actor.role === 'admin')

  if (!canReview) {
    return { ok: false, status: 403, code: 'not_authorized' }
  }

  if (!await dependencies.repository.targetIsAvailable(input.targetPersonId)) {
    return { ok: false, status: 409, code: 'target_unavailable' }
  }

  const created = await dependencies.repository.createAndAudit({
    targetPersonId: input.targetPersonId,
    normalizedEmail: email,
    actorUserId: dependencies.actor.userId,
  })

  try {
    await dependencies.repository.sendAuthInvitation(email, created.invitationId)
  } catch {
    await dependencies.repository.revokeAfterDeliveryFailure(created.invitationId)
    return { ok: false, status: 409, code: 'delivery_failed' }
  }

  return { ok: true, status: 201, ...created }
}
