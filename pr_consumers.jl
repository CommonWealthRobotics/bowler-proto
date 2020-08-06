using CSV
using DataFrames

const our_url = "git@github.com:CommonWealthRobotics/bowler-proto.git"
const required_tag_prefix = "refs/heads/" # TODO: Revert to "refs/tags/v"

# Derive our tag from the ref
github_ref = ENV["GITHUB_REF"]
our_tag = if startswith(github_ref, required_tag_prefix)
    github_ref[last(findfirst(required_tag_prefix, github_ref))+1:end]
else
    throw(ErrorException("Cannot update consumers with invalid tag name: $github_ref"))
end

consumers_csv_path = "consumers.csv"
consumers = DataFrame(CSV.File(consumers_csv_path))

for row in eachrow(consumers)
    pwd_before = pwd()
    try
        git_url = row["git_url"]
        user_name = row["user_name"]
        repo_name = row["repo_name"]
        dir = mktempdir()
        cd(dir)

        @info "Operating inside $dir"

        # Clone and move into the consumer to update
        run(`git clone $git_url --depth 1 $repo_name`)
        cd(repo_name)

        if !isdir("bowler-proto")
            # Need to add the submodule first
            run(`git submodule add $our_url`)
            run(`git submodule init`)
        end

        branch_name = "bowlerbot/update-protos"
        run(`git checkout -b $branch_name`)

        # Update the submodule
        cd("bowler-proto")
        run(`git fetch`)
        run(`git checkout $our_tag`)
        run(`git add .`)
        cd("..")

        # Commit and push
        run(`git commit -am "Update bowler-proto to $our_tag"`)
        run(`git push --force -u origin $branch_name`)

        # Open a PR
        run(`curl --request POST --url https://api.github.com/repos/$user_name/$repo_name/pulls --header 'Authorization: token $(ENV["TOKEN"])' --data '{"title":"Update bowler-proto", "head":"$branch_name", "base":"master"}'`)
    finally
        cd(pwd_before)
    end
end
