export function formatDate(
  date: Date | string | number | undefined,
  opts: Intl.DateTimeFormatOptions = {}
) {
  if (!date) return ""

  try {
    const options: Intl.DateTimeFormatOptions =
      opts.dateStyle || opts.timeStyle
        ? opts
        : {
            month: opts.month ?? "long",
            day: opts.day ?? "numeric",
            year: opts.year ?? "numeric",
            ...opts,
          }
    return new Intl.DateTimeFormat("en-US", options).format(new Date(date))
  } catch (err) {
    console.error(err)
    return ""
  }
}

export function formatTitle(title: string) {
  // capitalize the first letter of each word and replace underscores with spaces
  return title?.replace(/_/g, " ")?.replace(/\w\S*/g, (txt) => {
    return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
  })
}
