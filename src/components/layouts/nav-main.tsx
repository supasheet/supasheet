"use client"

import * as React from "react"

import { Link, useLocation } from "@tanstack/react-router"

import { HomeIcon } from "lucide-react"

import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "#/components/ui/sidebar"

import { NotificationsBell } from "./notifications-bell"

export function NavMain({
  items,
  schema,
}: {
  schema: string
  items: {
    title: string
    url: string
    icon?: React.ReactNode
  }[]
}) {
  const location = useLocation({
    select: (loc) => ({
      ...loc,
      pathname: loc.pathname.replace(/\/$/, ""),
    }),
  })

  return (
    <SidebarGroup>
      <SidebarGroupContent className="flex flex-col gap-2">
        <SidebarMenu>
          <SidebarMenuItem className="flex items-center gap-2">
            <SidebarMenuButton
              tooltip="Overview"
              className="min-w-8 bg-primary text-primary-foreground duration-200 ease-linear hover:bg-primary/90 hover:text-primary-foreground active:bg-primary/90 active:text-primary-foreground"
              render={<Link to={`/${schema}` as never} />}
            >
              <HomeIcon />
              <span>Overview</span>
            </SidebarMenuButton>
            <NotificationsBell />
          </SidebarMenuItem>
        </SidebarMenu>
        <SidebarMenu className="flex flex-col gap-1">
          {items.map((item) => (
            <SidebarMenuItem key={item.title}>
              <SidebarMenuButton
                tooltip={item.title}
                render={<Link to={`/${schema}/${item.url}` as never} />}
                isActive={location.pathname === `/${schema}${item.url}`}
              >
                {item.icon}
                <span>{item.title}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          ))}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  )
}
