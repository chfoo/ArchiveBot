module CommandPatterns
  AC = %r{([^\s]+)(?:\s+(.+))?}

  ARCHIVE           = %r{\A(?:\!a|\!archive) #{AC}\Z}
  ARCHIVEONLY       = %r{\A(?:\!ao|\!archiveonly) #{AC}\Z}
  ARCHIVEONLY_MANY  = %r{\A(?:\!ao|\!archiveonly)\s*<\s*#{AC}\Z}
end
