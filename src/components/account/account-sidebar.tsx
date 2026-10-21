import { Link, useLocation } from "@tanstack/react-router"

import {
  ArrowLeftIcon,
  ShieldUserIcon,
  UserCircle,
  UserCogIcon,
  UserIcon,
  UserPlusIcon,
} from "lucide-react"

import { NavSecondary } from "#/components/layouts/nav-secondary"
import { NavUser } from "#/components/layouts/nav-user"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "#/components/ui/sidebar"

const items = [
  {
    // name, profile picture, danger zone
    name: "Profile",
    url: "/account/profile",
    icon: <UserIcon />,
  },
  {
    // email, identities (google, github, etc)
    name: "Identities",
    url: "/account/identities",
    icon: <UserPlusIcon />,
  },
  {
    // password, mfa
    name: "Security",
    url: "/account/security",
    icon: <ShieldUserIcon />,
  },
  {
    // roles & permissions
    name: "Roles & Permissions",
    url: "/account/roles-permissions",
    icon: <UserCogIcon />,
  },
]

export function AccountSidebar() {
  const location = useLocation()
  return (
    <Sidebar collapsible="offcanvas" variant="floating">
      <SidebarHeader>
        <SidebarMenu className="px-2">
          <SidebarMenuItem>
            <SidebarMenuButton>
              <UserCircle className="size-5!" />
              <span className="text-base font-semibold">User</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarMenu className="flex flex-col gap-1">
            {items.map((item) => (
              <SidebarMenuItem key={item.name}>
                <SidebarMenuButton
                  tooltip={item.name}
                  render={<Link to={item.url as never} />}
                  isActive={location.pathname.startsWith(item.url)}
                >
                  {item.icon}
                  <span>{item.name}</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter>
        <NavSecondary
          items={[
            {
              title: "Back to Main",
              url: "/",
              icon: <ArrowLeftIcon className="size-5!" />,
            },
          ]}
        />
        <NavUser />
      </SidebarFooter>
    </Sidebar>
  )
}
