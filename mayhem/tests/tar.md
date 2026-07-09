# tar

> Archiving utility.
> Often combined with a compression method, such as gzip or bzip2.
> More information: <https://www.gnu.org/software/tar>.

- Create an archive from files:

`tar cf {{target.tar}} {{file1}} {{file2}} {{file3}}`

- Extract a (compressed) archive into the current directory:

`tar xf {{source.tar[.gz|.bz2|.xz]}}`

- List the contents of a tar file:

`tar tvf {{source.tar}}`
