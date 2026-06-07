# Test Patterns by Framework

各测试框架的模板和最佳实践。

## JUnit 5 + Mockito

### 单元测试模板

```java
@SpringBootTest
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private SmsService smsService;

    @Autowired
    @InjectMocks
    private UserService userService;

    // Given
    @BeforeEach
    void setUp() {
        // common setup
    }

    @Test
    void addUserTest() {
        // Scenario 1: normal
        User result = userService.addUser(buildValidUser());
        assertNotNull(result);
        assertEquals("张三", result.getName());

        // Scenario 2: empty name
        assertThrows(BizException.class, () -> userService.addUser(buildUserWithEmptyName()));

        // Scenario 3: null user
        assertThrows(IllegalArgumentException.class, () -> userService.addUser(null));
    }
}
```

### Controller 集成测试模板

```java
@SpringBootTest
@AutoConfigureMockMvc
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Test
    void getUserTest() throws Exception {
        // Given
        when(userService.findById(1L)).thenReturn(buildValidUser());

        // When + Then
        mockMvc.perform(get("/api/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("张三"));
    }
}
```

### Mock 规则

| 依赖类型 | Mock 策略 |
|---------|----------|
| Database / Repository | `@MockBean` |
| 外部 API / RPC | `@MockBean` |
| 内部 Service | 真实实例（仅测试目标类时 Mock） |
| 纯函数 / 工具类 | 真实实例，不 Mock |

### Mock Anti-Patterns

| 反模式 | 症状 | 修正 |
|--------|------|------|
| Mock behavior | mock 返回值直接复刻被测方法应该计算出的结果，测试只证明 mock 被调用 | 让被测逻辑真实运行，只 mock 数据库、外部 API、时间、随机数、网络等边界 |
| Test-only production method | 为测试新增生产代码专用 setter、public helper、debug flag 或绕过校验入口 | 优先使用公开 API、构造器注入、fixture 或测试容器；若可测性确实差，先把设计问题交给 `deep-plan` |
| Mock without contract | 不清楚依赖真实返回格式、异常、空值、幂等语义就写 mock | 先冻结 request/response/exception/empty-case contract，再写 mock 或 contract test |
| Incomplete mock | 只覆盖 happy path，失败分支、空集合、重试、副作用和 must-not 行为全靠默认值 | 为失败路径和禁止副作用补显式断言；默认值不能替代需求行为 |
| Integration as afterthought | 单元测试全绿，但跨模块 mapper、序列化、权限、事务、消息或异步状态未被验证 | 为跨边界行为增加 integration guard、static contract guard 或手工验证锚点 |

**判断句：** 如果移除 mock 后测试没有任何真实业务断言，或 mock 的排列组合比生产逻辑还复杂，这个测试大概率只是在测试 mock。

---

## Jest (JavaScript/TypeScript)

### 单元测试模板

```typescript
describe('UserService', () => {
  let service: UserService;
  let repo: Mock<userRepository>;

  beforeEach(() => {
    repo = new Mock<userRepository>();
    service = new UserService(repo as unknown as userRepository);
  });

  describe('createUser', () => {
    it('handles normal, empty name, and duplicate scenarios', () => {
      // Scenario 1: normal
      expect(() => service.createUser(validUser)).not.toThrow();
      expect(service.createUser(validUser)).toEqual({ id: 1, name: 'test' });

      // Scenario 2: empty name
      expect(() => service.createUser({ ...validUser, name: '' })).toThrow(ValidationException);

      // Scenario 3: duplicate email
      repo.findByEmail.mockResolvedValue(existingUser);
      expect(() => service.createUser(validUser)).toThrow(DuplicateException);
    });
  });
});
```

### React Component 测试模板

```typescript
describe('UserForm', () => {
  it('handles submit, validation, and error scenarios', () => {
    const { getByText, getByRole } = render(<UserForm onSubmit={mockOnSubmit} />);

    // Scenario 1: normal submit
    fireEvent.change(getByLabelText('名称'), { target: { value: '测试' } });
    fireEvent.click(getByRole('button', { name: 'submit' }));
    expect(mockOnSubmit).toHaveBeenCalledWith({ name: '测试' });

    // Scenario 2: empty required field
    fireEvent.click(getByRole('button', { name: 'submit' }));
    expect(getByText('名称不能为空')).toBeInTheDocument();

    // Scenario 3: API error
    mockOnSubmit.mockRejectedValue(new Error('Network error'));
    fireEvent.click(getByRole('button', { name: 'submit' }));
    expect(getByText('提交失败')).toBeInTheDocument();
  });
});
```

---

## Pytest (Python)

### 单元测试模板

```python
class TestUserService:
    def test_create_user(self):
        # Scenario 1: normal
        user = self.service.create_user(name="张三", email="z@test.com")
        assert user.id is not None
        assert user.name == "张三"

        # Scenario 2: empty name
        with pytest.raises(ValidationError):
            self.service.create_user(name="", email="a@b.com")

        # Scenario 3: duplicate email
        with pytest.raises(DuplicateError):
            self.service.create_user(name="李四", email="z@test.com")
```

### FastAPI 集成测试模板

```python
@pytest.fixture
def client():
    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)

class TestUserAPI:
    def test_get_user(self, client):
        response = client.get("/api/users/1")
        assert response.status_code == 200
        assert response.json()["name"] == "张三"
```

---

## Go Testing

### 单元测试模板

```go
func TestCreateUser(t *testing.T) {
    // Scenario 1: normal
    user, err := service.CreateUser("张三", "z@test.com")
    assert.Nil(t, err)
    assert.Equal(t, "张三", user.Name)

    // Scenario 2: empty name
    _, err = service.CreateUser("", "a@b.com")
    assert.Error(t, err)
    assert.Contains(t, err.Error(), "name is required")

    // Scenario 3: nil input
    assert.Panics(t, func() { service.CreateUser("a", "") })
}
```

---

## Naming Convention

Detect from existing tests (Phase 2, Pattern #8). Common conventions:
- `testMethod_Scenario` (e.g., `testAddUser_normal`)
- `should_xxx` (e.g., `should_return_error_when_null`)

**IMPORTANT:** Use whatever convention the project already uses. Do NOT invent your own.

## Scenario Merging

**Follow detected patterns.** If existing tests merge scenarios into one method, do the same. If they separate, separate.

**Default when no existing tests:** Ask user preference (Phase 4).
