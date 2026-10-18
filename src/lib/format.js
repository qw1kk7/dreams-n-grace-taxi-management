const peso = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP', maximumFractionDigits: 0 })

export const formatPeso = (n) => (n == null ? '' : peso.format(n))

export const formatDate = (d) =>
  d ? new Date(`${d}T00:00:00`).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' }) : ''

export const today = () => new Date().toLocaleDateString('en-CA')

// Whole years between two ISO dates, the same way Postgres age() counts them.
export function yearsBetween(from, to = today()) {
  if (!from) return null
  const [fy, fm, fd] = from.split('-').map(Number)
  const [ty, tm, td] = to.split('-').map(Number)
  let years = ty - fy
  if (tm < fm || (tm === fm && td < fd)) years -= 1
  return years
}

// The boundary rate in force today for a unit of the given age.
export function rateForAge(rates, age, on = today()) {
  return rates
    .filter(
      (r) =>
        age >= r.min_unit_age_years &&
        (r.max_unit_age_years == null || age < r.max_unit_age_years) &&
        on >= r.effective_from &&
        (r.effective_to == null || on <= r.effective_to),
    )
    .sort((a, b) => (a.effective_from < b.effective_from ? 1 : -1))[0]
}

export const formatYears = (n) => (n == null ? '' : `${n} yr${n === 1 ? '' : 's'}`)
