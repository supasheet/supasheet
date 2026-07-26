import type { Provider } from "@supabase/supabase-js"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import { supabase } from "#/lib/supabase/client"
import { cn } from "#/lib/utils.ts"

const PROVIDER_SLUG_OVERRIDES: Record<string, string> = {
  azure: "microsoft",
  linkedin_oidc: "linkedin",
  slack_oidc: "slack",
}

function providerSlug(provider: string): string {
  return PROVIDER_SLUG_OVERRIDES[provider] ?? provider
}

function providerLabel(provider: string): string {
  return providerSlug(provider)
    .split(/[_-]/)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ")
}

function providerIconUrl(provider: string): string {
  if (provider === "github") return `https://supabase.com/docs/img/icons/github-icon-light.svg`
  return `https://supabase.com/docs/img/icons/${providerSlug(provider)}-icon.svg`
}

async function signInWithOAuth(provider: string) {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: provider as Provider,
  })
  if (error) toast.error(error.message)
}

export function OAuthProviderButtons({ providers }: { providers: string[] }) {
  if (providers.length === 0) return null

  return (
    <div className={cn("grid gap-2", providers.length > 1 && "grid-cols-2")}>
      {providers.map((provider) => (
        <Button
          key={provider}
          variant="outline"
          onClick={() => signInWithOAuth(provider)}
        >
          <img
            src={providerIconUrl(provider)}
            alt=""
            className="size-4"
            onError={(e) => {
              e.currentTarget.style.display = "none"
            }}
          />
          {providerLabel(provider)}
        </Button>
      ))}
    </div>
  )
}
