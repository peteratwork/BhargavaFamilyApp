import type { CreateInvitationInput } from './handler.ts'

export type ParsedInvitationRequest =
  | { ok: true; input: CreateInvitationInput }
  | { ok: false; code: 'invalid_request' }

export async function parseInvitationRequest(
  request: Request,
): Promise<ParsedInvitationRequest> {
  let body: unknown
  try {
    body = await request.json()
  } catch {
    return { ok: false, code: 'invalid_request' }
  }

  if (
    typeof body !== 'object' || body === null ||
    !('targetPersonId' in body) || !('email' in body)
  ) {
    return { ok: false, code: 'invalid_request' }
  }

  const { targetPersonId, email } = body as Record<string, unknown>
  if (typeof targetPersonId !== 'string' || typeof email !== 'string') {
    return { ok: false, code: 'invalid_request' }
  }

  return { ok: true, input: { targetPersonId, email } }
}
