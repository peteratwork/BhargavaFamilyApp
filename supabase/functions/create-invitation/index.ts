import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.57.4'

import {
  createInvitation,
  type Actor,
  type InvitationRepository,
} from './handler.ts'

const supabaseURL = Deno.env.get('SUPABASE_URL') ?? ''
const publishableKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const invitationRedirectURL = Deno.env.get('INVITATION_REDIRECT_URL') ?? ''

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  correlationID: string,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-correlation-id': correlationID,
    },
  })
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

class SupabaseInvitationRepository implements InvitationRepository {
  constructor(
    private readonly client: SupabaseClient,
    private readonly redirectURL: string,
    private readonly actorUserID: string,
  ) {}

  async targetIsAvailable(personId: string): Promise<boolean> {
    const { data: person, error: personError } = await this.client
      .from('people')
      .select('id')
      .eq('id', personId)
      .eq('is_verified', true)
      .maybeSingle()
    if (personError) throw personError
    if (!person) return false

    const { data: account, error: accountError } = await this.client
      .from('accounts')
      .select('user_id')
      .eq('person_id', personId)
      .maybeSingle()
    if (accountError) throw accountError
    if (account) return false

    const { data: invitation, error: invitationError } = await this.client
      .from('invitations')
      .select('id')
      .eq('target_person_id', personId)
      .eq('status', 'pending')
      .maybeSingle()
    if (invitationError) throw invitationError
    return invitation === null
  }

  async createAndAudit(input: {
    targetPersonId: string
    normalizedEmail: string
    actorUserId: string
  }): Promise<{ invitationId: string; expiresAt: string }> {
    const tokenHash = await sha256(`${crypto.randomUUID()}:${input.normalizedEmail}`)
    const { data, error } = await this.client.rpc('create_invitation_record', {
      p_target_person_id: input.targetPersonId,
      p_normalized_email: input.normalizedEmail,
      p_actor_user_id: input.actorUserId,
      p_token_hash: tokenHash,
    })
    if (error) throw error
    const row = Array.isArray(data) ? data[0] : data
    if (!row?.invitation_id || !row?.expires_at) throw new Error('invitation_transaction_failed')
    return { invitationId: row.invitation_id, expiresAt: row.expires_at }
  }

  async sendAuthInvitation(email: string, invitationId: string): Promise<void> {
    const { error } = await this.client.auth.admin.inviteUserByEmail(email, {
      redirectTo: this.redirectURL,
      data: { invitation_id: invitationId },
    })
    if (error) throw error
  }

  async revokeAfterDeliveryFailure(invitationId: string): Promise<void> {
    const { error } = await this.client.rpc('revoke_invitation_after_delivery_failure', {
      p_invitation_id: invitationId,
      p_actor_user_id: this.actorUserID,
    })
    if (error) throw error
  }
}

Deno.serve(async (request) => {
  const correlationID = request.headers.get('x-correlation-id') ?? crypto.randomUUID()
  if (request.method !== 'POST') {
    return jsonResponse({ code: 'method_not_allowed' }, 405, correlationID)
  }

  const authorization = request.headers.get('authorization')
  if (!authorization?.startsWith('Bearer ')) {
    return jsonResponse({ code: 'authentication_required' }, 401, correlationID)
  }

  if (!supabaseURL || !publishableKey || !serviceRoleKey || !invitationRedirectURL) {
    return jsonResponse({ code: 'service_unavailable' }, 503, correlationID)
  }

  try {
    const userClient = createClient(supabaseURL, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) {
      return jsonResponse({ code: 'authentication_required' }, 401, correlationID)
    }

    const { data: account, error: accountError } = await userClient
      .from('accounts')
      .select('role,status')
      .eq('user_id', userData.user.id)
      .single()
    if (accountError || !account) {
      return jsonResponse({ code: 'not_authorized' }, 403, correlationID)
    }

    const body = await request.json() as { targetPersonId?: unknown; email?: unknown }
    if (typeof body.targetPersonId !== 'string' || typeof body.email !== 'string') {
      return jsonResponse({ code: 'invalid_request' }, 400, correlationID)
    }

    const actor: Actor = {
      userId: userData.user.id,
      role: account.role,
      status: account.status,
    }
    const serviceClient = createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const result = await createInvitation(
      { targetPersonId: body.targetPersonId, email: body.email },
      {
        actor,
        repository: new SupabaseInvitationRepository(
          serviceClient,
          invitationRedirectURL,
          actor.userId,
        ),
      },
    )

    if (!result.ok) return jsonResponse({ code: result.code }, result.status, correlationID)
    return jsonResponse(
      { invitationId: result.invitationId, expiresAt: result.expiresAt },
      result.status,
      correlationID,
    )
  } catch {
    return jsonResponse({ code: 'service_unavailable' }, 503, correlationID)
  }
})
