import { HugeiconsIcon, IconSvgElement } from '@hugeicons/react'
import {
  Add01Icon, Alert02Icon, ArrowDown01Icon, ArrowLeft01Icon, ArrowRight01Icon, ArrowRight02Icon, Book02Icon, BookOpen01Icon,
  Bookmark01Icon, Cancel01Icon, ChartHistogramIcon, CheckmarkSquare02Icon, Database01Icon, Delete02Icon, Download04Icon,
  FilterHorizontalIcon, FilterIcon, Folder01Icon, Globe02Icon, Home09Icon, Layers01Icon, LibraryIcon, MoreHorizontalIcon,
  Notification03Icon, PinIcon, PlayIcon, PuzzleIcon, Refresh01Icon, Search01Icon, SecurityWarningIcon, Sorting01Icon,
  SparklesIcon, Tick02Icon, Undo02Icon, Settings01Icon, FaceIdIcon, SquareLock02Icon, PreviousIcon, NextIcon,
  ScrollVerticalIcon, BookOpen02Icon, InformationCircleIcon, ShuffleIcon,
} from '@hugeicons/core-free-icons'

const ICONS = {
  home: Home09Icon,
  library: LibraryIcon,
  search: Search01Icon,
  sources: PuzzleIcon,
  bell: Notification03Icon,
  stats: ChartHistogramIcon,
  back: ArrowLeft01Icon,
  globe: Globe02Icon,
  download: Download04Icon,
  refresh: Refresh01Icon,
  bookmark: Bookmark01Icon,
  bookmarkFill: Bookmark01Icon,
  check: Tick02Icon,
  sort: Sorting01Icon,
  select: CheckmarkSquare02Icon,
  layers: Layers01Icon,
  sparkle: SparklesIcon,
  plus: Add01Icon,
  x: Cancel01Icon,
  chevronDown: ArrowDown01Icon,
  chevronRight: ArrowRight01Icon,
  shield: SecurityWarningIcon,
  alert: Alert02Icon,
  database: Database01Icon,
  filter: FilterIcon,
  sliders: FilterHorizontalIcon,
  folder: Folder01Icon,
  book: BookOpen01Icon,
  books: Book02Icon,
  undo: Undo02Icon,
  arrowRight: ArrowRight02Icon,
  trash: Delete02Icon,
  pin: PinIcon,
  play: PlayIcon,
  more: MoreHorizontalIcon,
  settings: Settings01Icon,
  faceId: FaceIdIcon,
  lock: SquareLock02Icon,
  prev: PreviousIcon,
  next: NextIcon,
  webtoon: ScrollVerticalIcon,
  paged: BookOpen02Icon,
  info: InformationCircleIcon,
  shuffle: ShuffleIcon,
} satisfies Record<string, IconSvgElement>

/** Icons drawn solid instead of outlined. */
const SOLID = new Set(['play', 'bookmarkFill'])

export type IconName = keyof typeof ICONS

export function Icon({ name, size = 20, stroke = 1.8, label }: { name: IconName; size?: number; stroke?: number; label?: string }) {
  const a11y = label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': true as const }
  return (
    <HugeiconsIcon
      icon={ICONS[name]}
      size={size}
      strokeWidth={stroke}
      color="currentColor"
      {...(SOLID.has(name) ? { fill: 'currentColor' } : {})}
      {...a11y}
    />
  )
}
