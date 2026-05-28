defmodule Trinity.SingleNode.TraceParityTest do
  use ExUnit.Case, async: true

  alias Trinity.Bridge.Trace.Hash
  alias Trinity.SingleNode.RuntimeSupervisor

  @cases_path Path.expand(
                "../../../../../examples/qwen_router_prompt_eval/fixtures/qwen_router_prompt_eval_cases.json",
                __DIR__
              )

  @expected_hashes %{
    "ambiguous_decomposition" =>
      "44cae520a16e9393afbdbc7d510171d3facbf127bbc6e12532144614bcc25740",
    "architectural_decision" =>
      "e5d5ff78f67d75f34891b3c87a1375fbaa7b3624608232216763e8ce2683e77f",
    "code_debug" => "e21384d044dbf76c0a2145177d89dd8da76a24f211fdb35871451c32938249af",
    "contradiction" => "d07994db9a10350284d176c4dd0d51a655ed0d75a2135215ed3b980031c11000",
    "creative_but_constrained" =>
      "eb53a2ebfcb8c4459cbdbf43b0a6c7ea23df7a4c5e4f3de77bbbf9785613607b",
    "creative_request" => "4b91c97072330841054bffb9e427770e6d9778aaef99df856b4bdcdb2b83ecbb",
    "customer_apology" => "0b7b7c89eaf638062705241c721bd5f7b0f4dd68e3a38ef4f43ce795fa5cda84",
    "design_critique" => "4052797f6a7873442174c84d120768ae5606c26b97ce0cb0d1803f62a04e443a",
    "distributed_systems" => "d8b8bcef1591cf8052495295f0fb94739fa79dc1accca7f4e773fa2ff9fd183a",
    "empty_response" => "5d63f32757061c4ff68a2c7d2174f787ae37b40434b7a21c2a21ed674dc2717f",
    "empty_user" => "be41c1b7983955461d4dda2096c62a6fb3eeab8aa5bcf6efb38d570d7f02217e",
    "escalate_to_human" => "911ecc79cf2fe9f10dabd5c670b0c21c714e8e1f931b086ed0d514f769a21ae4",
    "final_answer_check" => "fdac2777adcc553a1bf767eaae47bc3a39ae6638576ff1fdfe7395402c871c29",
    "haskell_types" => "a2a0cb8177ea5c6e2b5caa51a08ba796751bbf46c76259668dcf42056f10f41b",
    "hypothesis_design" => "6ee487469141f25ae3927c49f01cbffbd6a51dd22716bc1ea482982f1930007c",
    "latex_math" => "a73bba8ffb01bdf30dd6dba90eaaab6a723ad770ade32e66f2ec930e9b1de850",
    "long_system_prompt" => "e5774a3d9b2cdb2d89147c50d487c38c3795435ee49c54ee102404d1c02d568b",
    "longer_context" => "32499a1e77a246eea30ba0d473addbb865f343740bc1072d5c326f5fb0cae535",
    "math_direct" => "5a4b9df623852c10e59e1d55495a5bb8da25dfd3940949aeaeeaf4e9560c47a0",
    "math_proof" => "89ef58afa21a249a59b29a248777553129cab25879ccef5dbeb2d82106af113d",
    "needs_revision" => "14394536717cc74f6312071cf03997a63460059221dcd9905c1dcf4f4297e91f",
    "performance_question" => "38bb730ffec01b5f433befccde45759a2391471bf98ca29248f53ba23637609b",
    "planning" => "23e4005e89d3be4079424c8eacc62b2479382190da0f501cbe099887b9e884a9",
    "product_decision" => "aaebaf9efb558b5ce518e15bf3b28ef41f046a37e7065b1f4f81eb6b7ef79d09",
    "provider_failure_triage" =>
      "48a42a5da6386ed597fc7a3173b602c0c420e20606ef72c1a2a981547a282479",
    "refactor_smell" => "9709c33571655f4361a17c28b16100c57af8eb1966e1e90cd9551feb3fba2028",
    "risk_assessment" => "1e2c541b2c0104439feacf5384bd4a877e0ac648a3f8718c789b900a21c92e30",
    "root_cause" => "ff8f30222327f6557e3e88cb4dd3503643cce27782416e508d77d227b1ccbe5c",
    "security_review" => "1536ff79f678270e272da2b787dc577fcaed2043728b044b8217f2e6a9cc37cd",
    "sql_query" => "9cdddde915f5110f0b5cc0ec45b42e5413d441ee51485ed8551f704e11be1dd4",
    "strategic_tradeoff" => "d42969839cde07fe6e4f215a62e5ede53d6b03bd139a69ddf5a4c082f9e5ff94",
    "thinker_breakdown" => "c44455a24d47dd310798a6493eb7aeb98fcd5171fc266e277294031052ba15cb",
    "two_assistant_turns" => "5eb2280d8f6eb91f1241d5ba0750dc530c3e27872155b930802e7b48761254ec",
    "unicode_emoji" => "f4790e10ddc11476c2bc73cec9a52daeab3a6ed48a1f3d4f2af27eef88cf522e",
    "unicode_normalization" => "dd5fbb8d1a3ac6a865af35c1ac75879050708de1dd4e2c79c700fb0d4aeee08b",
    "verification_after_worker" =>
      "2c2b43cae6155370016a93a863e720938c978ebe9a271233909bb38da6271061",
    "verify_simple" => "04176854656a6190634ae8d37a2dec147660721c211e45a6c802d40921a7767c"
  }

  test "37 prompt-eval transcript hashes match the coordinator baseline" do
    cases = fixture_cases()

    assert length(cases) == 37

    for %{"id" => id, "messages" => messages} <- cases do
      assert Hash.messages(messages) == Map.fetch!(@expected_hashes, id)
    end
  end

  test "route hash inputs preserve the seven-key coordinator contract" do
    plan = RuntimeSupervisor.extraction_plan([], runtime_profile: :mock_tiny)

    route_hash_inputs = %{
      artifact_ref: plan.artifact_ref.artifact_ref,
      head_ref: "head:qwen3-0.6b-sakana",
      selected_role_id: 2,
      selected_agent_id: 4,
      runtime_profile: :mock_tiny,
      margin_defaults: %{agent: 0.24, role: 1.06},
      route_head_spec: %{num_agents: 7, num_roles: 3}
    }

    assert Hash.term(route_hash_inputs) ==
             "7cb45f594d2dc0003569ed0cedddc377d154b3ebfeca16d85988862c117342ea"
  end

  defp fixture_cases do
    @cases_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
  end
end
